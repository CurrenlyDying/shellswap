#!/bin/sh
# Script to download and install the latest shellswap .deb package from GitHub Releases.
# Simplified to use only curl, grep, and sed for release parsing.
# Colors fixed using printf %b.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="CurrenlyDying"
REPO_NAME="shellswap"
DEB_NAME_PREFIX="shellswap" # Used to help identify the .deb file
GITHUB_API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

# --- Color Definitions ---
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

# --- Helper Functions ---
_log_prefix() {
    # $1: Color variable (e.g., GREEN)
    # $2: Level String (e.g., "INFO")
    # Use %b to interpret backslash escapes in $1, $BOLD, and $RESET variables
    printf "%b%b[%s]%b " "$1" "$BOLD" "$2" "$RESET"
}
echo_step() {
    # $1: Message
    # Use %b to interpret backslash escapes in $BLUE, $BOLD, and $RESET variables
    printf "\n%b==> %b%s%b\n" "$BLUE" "$BOLD" "$1" "$RESET"
}
echo_info() {
    # The output of _log_prefix already contains processed escape sequences,
    # so we print it as a string (%s). $1 is the message text.
    printf "%s%s\n" "$(_log_prefix "$GREEN" "INFO")" "$1"
}
echo_warning() {
    printf "%s%s\n" "$(_log_prefix "$YELLOW" "WARN")" "$1"
}
echo_error() {
    printf "%s%s\n" "$(_log_prefix "$RED" "ERROR")" "$1" >&2
}

# --- Determine Architecture ---
ARCH=""
case $(uname -m) in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armhf" ;;
    *)
        echo_error "Unsupported architecture for .deb: $(uname -m)"
        exit 1
        ;;
esac
# We expect asset names like: shellswap_VERSION_amd64.deb
# So we will grep for a URL containing DEB_NAME_PREFIX and _${ARCH}.deb
EXPECTED_DEB_NAME_PARTIAL_PATTERN="${DEB_NAME_PREFIX}"
EXPECTED_DEB_SUFFIX_PATTERN="_${ARCH}.deb"

# --- Main Script ---
echo_step "Starting shellswap .deb package installation"

if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

# Check for essential commands
for cmd in curl grep sed basename mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo_error "'$cmd' is required but not installed. Please install it."
        exit 1
    fi
done
if ! command -v apt >/dev/null 2>&1 && ! command -v dpkg >/dev/null 2>&1; then
    echo_error "'apt' and 'dpkg' commands not found. Cannot install .deb package."
    exit 1
fi

echo_info "Fetching latest release information for ${MAGENTA}${REPO_OWNER}/${REPO_NAME}${RESET}..."
RELEASE_INFO=$(curl -sSL "${GITHUB_API_URL}")

if [ -z "$RELEASE_INFO" ]; then
    echo_error "Failed to fetch release information. Check network or repository URL."
    exit 1
fi

DOWNLOAD_URL=""
ASSET_NAME=""

echo_info "Attempting to find .deb asset URL using 'grep' and 'sed'..."

# Strategy:
# 1. Grep all browser_download_url lines from the JSON.
# 2. From those, further grep for lines that contain our expected name prefix AND suffix.
# 3. Extract the URL using sed.
# This assumes the URL itself will contain identifiable parts of the .deb filename.
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | \
    grep -Eo "\"browser_download_url\": \"[^\"]*\"" | \
    grep "${EXPECTED_DEB_NAME_PARTIAL_PATTERN}" | \
    grep "${EXPECTED_DEB_SUFFIX_PATTERN}" | \
    sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' | \
    head -n 1)


if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_error "Could not find download URL for a .deb package matching pattern '${MAGENTA}${EXPECTED_DEB_NAME_PARTIAL_PATTERN}...${EXPECTED_DEB_SUFFIX_PATTERN}${RESET}'."
    echo_error "Please check assets on GitHub Releases and their naming. The script uses 'grep' and 'sed' for parsing."
    exit 1
fi

ASSET_NAME=$(basename "$DOWNLOAD_URL")
if [ -z "$ASSET_NAME" ]; then
    ASSET_NAME="${DEB_NAME_PREFIX}_package${EXPECTED_DEB_SUFFIX_PATTERN}" # Generic fallback name
    echo_warning "Could not determine exact asset name from URL, using generic: ${ASSET_NAME}"
fi

echo_info "Found .deb package URL. Deduced asset name: ${MAGENTA}${ASSET_NAME}${RESET}"

TEMP_DIR=$(mktemp -d)
trap 'echo_info "Cleaning up temporary directory: ${TEMP_DIR}"; rm -rf "$TEMP_DIR"' EXIT

TEMP_DEB_PATH="${TEMP_DIR}/${ASSET_NAME}"

echo_step "Downloading ${ASSET_NAME}"
echo_info "URL: ${DOWNLOAD_URL}"
if ! curl -Lf --progress-bar -o "${TEMP_DEB_PATH}" "${DOWNLOAD_URL}"; then
    echo_error "Failed to download .deb package from ${DOWNLOAD_URL}"
    exit 1
fi

echo_step "Verifying download"
if [ ! -s "${TEMP_DEB_PATH}" ]; then
    echo_error "Downloaded file is empty."
    exit 1
fi
echo_info "Download verified."

echo_step "Installing .deb package"
INSTALL_SUCCESS=0
if command -v apt >/dev/null 2>&1; then
    echo_info "Attempting installation with 'apt install'..."
    echo_info "Updating package lists (apt update)..."
    if ! apt update -qq; then
        echo_warning "'apt update' failed. Proceeding with install attempt, but dependencies might not be found if lists are stale."
    fi

    if apt install -y "${TEMP_DEB_PATH}"; then
        echo_info "${GREEN}${BOLD}${DEB_NAME_PREFIX} installed successfully using apt!${RESET}" # Note: GREEN and BOLD are variables here
        INSTALL_SUCCESS=1
    else
        echo_warning "'apt install' failed. This might be due to unmet dependencies or other issues."
    fi
else
    echo_warning "'apt' command not found. Will proceed with 'dpkg -i'."
fi

if [ "$INSTALL_SUCCESS" -eq 0 ]; then
    if command -v dpkg >/dev/null 2>&1; then
        echo_info "Attempting installation with 'dpkg -i'..."
        if dpkg -i "${TEMP_DEB_PATH}"; then
            # Use %b for YELLOW, BOLD, RESET when printing the warning string directly
            printf "%b%b%s installed with dpkg.%b Dependencies might be missing.\n" "$YELLOW" "$BOLD" "$DEB_NAME_PREFIX" "$RESET"
            if command -v apt >/dev/null 2>&1; then
                 # Use %b for MAGENTA and RESET
                 printf "%bPlease run %bsudo apt --fix-broken install%b to resolve any dependency issues.%b\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "$RESET" "$RESET" # Bit complex, let's simplify
                 echo_info "Please run ${MAGENTA}sudo apt --fix-broken install${RESET} to resolve any dependency issues." # Simpler
            else
                echo_warning "Cannot advise 'apt --fix-broken install' as 'apt' is not available."
            fi
            INSTALL_SUCCESS=1
        else
            echo_error "'dpkg -i' also failed."
            echo_error "Failed to install .deb package. Please check the output for errors."
            exit 1
        fi
    else
        echo_error "'dpkg' command not found, and 'apt' failed or was not available. Cannot install .deb package."
        exit 1
    fi
fi

if [ "$INSTALL_SUCCESS" -eq 1 ]; then
     # Use %b for MAGENTA and RESET
     printf "%bYou should now be able to run the installed command, likely: %bsudo shellswap%b%b\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "$RESET" "$RESET" # Simpler
     echo_info "You should now be able to run the installed command, likely: ${MAGENTA}sudo shellswap${RESET}"
fi

exit 0
