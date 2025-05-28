#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>     // For geteuid()
#include <sys/stat.h>   // For chmod()
#include <sys/types.h>  // For mode_t in chmod()

#define PASSWD_FILE "/etc/passwd"
#define TEMP_PASSWD_FILE "/etc/passwd.tmp"
#define ROOT_BASH_LINE "root:x:0:0:root:/root:/bin/bash"
#define ROOT_ZSH_LINE "root:x:0:0:root:/root:/bin/zsh"
#define LINE_BUFFER_SIZE 256 // Should be ample for /etc/passwd lines

// Function to remove trailing newline, if any
void strip_newline(char *str) {
    size_t len = strlen(str);
    if (len > 0 && str[len - 1] == '\n') {
        str[len - 1] = '\0';
    }
}

int main() {
    FILE *fp_passwd = NULL;
    FILE *fp_temp = NULL;
    char line_buffer[LINE_BUFFER_SIZE];
    char first_line_original[LINE_BUFFER_SIZE]; // To store the original first line with newline for writing back if no swap
    int swapped = 0;
    const char *new_shell_line = NULL;
    const char *success_message = NULL;

    // Check 1: Ensure the program is run as root
    if (geteuid() != 0) {
        fprintf(stderr, "Error: This program must be run as root.\n");
        return 1;
    }

    // Open the original passwd file for reading
    fp_passwd = fopen(PASSWD_FILE, "r");
    if (fp_passwd == NULL) {
        perror("Error opening " PASSWD_FILE " for reading");
        return 1;
    }

    // Open a temporary file for writing
    // Important: Create temp file in the same directory as the target file (/etc)
    // to ensure atomic rename and correct permissions inheritance (usually).
    fp_temp = fopen(TEMP_PASSWD_FILE, "w");
    if (fp_temp == NULL) {
        perror("Error opening " TEMP_PASSWD_FILE " for writing");
        fclose(fp_passwd);
        return 1;
    }

    // Read the first line from /etc/passwd
    if (fgets(line_buffer, sizeof(line_buffer), fp_passwd) == NULL) {
        if (feof(fp_passwd)) {
            fprintf(stderr, "Error: %s is empty or could not read the first line.\n", PASSWD_FILE);
        } else {
            perror("Error reading first line from " PASSWD_FILE);
        }
        fclose(fp_passwd);
        fclose(fp_temp);
        remove(TEMP_PASSWD_FILE); // Clean up temp file
        return 1;
    }
    
    // Store the original first line (including potential newline)
    strncpy(first_line_original, line_buffer, sizeof(first_line_original) -1);
    first_line_original[sizeof(first_line_original)-1] = '\0'; // Ensure null termination

    // Remove trailing newline for comparison
    strip_newline(line_buffer);

    // Determine if a swap is needed
    if (strcmp(line_buffer, ROOT_BASH_LINE) == 0) {
        new_shell_line = ROOT_ZSH_LINE;
        success_message = "Swapped root shell from /bin/bash to /bin/zsh.";
        swapped = 1;
    } else if (strcmp(line_buffer, ROOT_ZSH_LINE) == 0) {
        new_shell_line = ROOT_BASH_LINE;
        success_message = "Swapped root shell from /bin/zsh to /bin/bash.";
        swapped = 1;
    } else {
        // First line is not one of the expected root shell configurations
        fprintf(stderr, "Error: The first line of %s does not match the expected root shell configuration for bash or zsh.\n", PASSWD_FILE);
        fprintf(stderr, "Found: \"%s\"\n", line_buffer);
        fprintf(stderr, "No changes made.\n");
        
        // No swap, so write the original first line back to ensure the temp file isn't empty
        // if we were to proceed (but we are exiting).
        // However, it's safer to just abort and not touch the temp file further if no swap.
        fclose(fp_passwd);
        fclose(fp_temp);
        remove(TEMP_PASSWD_FILE); // Clean up temp file
        return 1; // Indicate an issue / no action taken
    }

    // Write the new (swapped) first line or the original if no swap was intended (already handled by exiting)
    if (fprintf(fp_temp, "%s\n", new_shell_line) < 0) {
        perror("Error writing swapped line to temporary file");
        fclose(fp_passwd);
        fclose(fp_temp);
        remove(TEMP_PASSWD_FILE);
        return 1;
    }

    // Copy the rest of the original /etc/passwd file to the temporary file
    while (fgets(line_buffer, sizeof(line_buffer), fp_passwd) != NULL) {
        if (fputs(line_buffer, fp_temp) == EOF) {
            perror("Error writing subsequent line to temporary file");
            fclose(fp_passwd);
            fclose(fp_temp);
            remove(TEMP_PASSWD_FILE);
            return 1;
        }
    }

    // Check for read errors on the original passwd file (apart from EOF)
    if (ferror(fp_passwd)) {
        perror("Error reading from " PASSWD_FILE);
        fclose(fp_passwd);
        fclose(fp_temp);
        remove(TEMP_PASSWD_FILE);
        return 1;
    }

    // Close both files
    fclose(fp_passwd);
    if (fclose(fp_temp) == EOF) { // fclose can fail, e.g., if disk is full
        perror("Error closing temporary file " TEMP_PASSWD_FILE);
        // Attempt to remove the temp file as it might be corrupted or incomplete
        remove(TEMP_PASSWD_FILE);
        return 1;
    }

    // Set correct permissions for the temporary file before renaming
    // /etc/passwd should be 0644 (rw-r--r--)
    if (chmod(TEMP_PASSWD_FILE, 0644) != 0) {
        perror("Error setting permissions on " TEMP_PASSWD_FILE);
        remove(TEMP_PASSWD_FILE); // Clean up
        return 1;
    }

    // Atomically replace the original /etc/passwd with the temporary file
    if (rename(TEMP_PASSWD_FILE, PASSWD_FILE) != 0) {
        perror("CRITICAL: Error renaming " TEMP_PASSWD_FILE " to " PASSWD_FILE);
        fprintf(stderr, "The original %s is UNCHANGED.\n", PASSWD_FILE);
        fprintf(stderr, "The modified content is in %s. Manual intervention may be required.\n", TEMP_PASSWD_FILE);
        // Do NOT remove TEMP_PASSWD_FILE here, as it contains the intended changes.
        return 1;
    }

    printf("%s\n", success_message);
    printf("%s has been updated successfully.\n", PASSWD_FILE);

    return 0; // Success
}
