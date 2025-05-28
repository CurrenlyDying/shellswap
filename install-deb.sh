#!/bin/sh
# Script to download and install the latest shellswap .deb package from GitHub Releases.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="CurrenlyDying"
REPO_NAME="shellswap"
DEB_NAME_PREFIX="shellswap"
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
    printf "%s%s%s%s " "$1" "$BOLD" "[$2]" "$RESET"
}
echo_step() {
    printf "\n%s==> %s%s%s\n" "$BLUE" "$BOLD" "$1" "$RESET"
}
echo_info() {
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
EXPECTED_DEB_PATTERN_SUFFIX="_${ARCH}.deb"
# Regex for awk to match asset name (e.g. shellswap_ANYTHING_amd64.deb)
DEB_NAME_REGEX_PATTERN="^${DEB_NAME_PREFIX}[^[:space:]\"]*${EXPECTED_DEB_PATTERN_SUFFIX}$"

# --- Main Script ---
echo_step "Starting shellswap .deb package installation"

if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo_error "'curl' is required but not installed. Please install curl."
    exit 1
fi
JQ_CMD=$(command -v jq || true)
AWK_CMD=$(command -v awk || true)
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

if [ -n "$JQ_CMD" ]; then
    echo_info "Attempting to find .deb asset using 'jq'..."
    ASSET_INFO_JSON=$("$JQ_CMD" -r ".assets[] | select(.name | startswith(\"${DEB_NAME_PREFIX}\") and endswith(\"${EXPECTED_DEB_PATTERN_SUFFIX}\")) | {name, url: .browser_download_url} | input_filename=\"-\" " <<< "$RELEASE_INFO" | head -n 1) # Get first match as JSON object
    if [ -n "$ASSET_INFO_JSON" ] && [ "$ASSET_INFO_JSON" != "null" ]; then
        ASSET_NAME=$(echo "$ASSET_INFO_JSON" | "$JQ_CMD" -r '.name')
        DOWNLOAD_URL=$(echo "$ASSET_INFO_JSON" | "$JQ_CMD" -r '.url')
    fi
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    if [ -n "$JQ_CMD" ]; then
        echo_warning "Failed to find .deb asset using 'jq', or 'jq' is not installed/functional."
    else
        echo_warning "'jq' not found."
    fi

    if [ -n "$AWK_CMD" ]; then
        echo_info "Attempting to find .deb asset using 'awk' fallback..."
        AWK_OUTPUT=$(echo "$RELEASE_INFO" | "$AWK_CMD" -v name_regex="$DEB_NAME_REGEX_PATTERN" '
            BEGIN { RS="},{" } # Split records by asset separator-ish
            /"name"[[:space:]]*:[[:space:]]*"'/ { # Basic check for a "name" field start
                current_name=""
                # Extract current asset name using match()
                if (match($0, /"name"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr_name)) {
                    current_name=arr_name[1]
                }

                if (current_name ~ name_regex) { # Regex match for .deb name
                    # If name matches, extract its browser_download_url
                    if (match($0, /"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr_url)) {
                        printf "%s\n%s\n", current_name, arr_url[1] # Output name then URL
                        exit # Found it
                    }
                }
            }
        ')
        if [ -n "$AWK_OUTPUT" ]; then
            ASSET_NAME=$(echo "$AWK_OUTPUT" | sed -n '1p') # First line is asset name
            DOWNLOAD_URL=$(echo "$AWK_OUTPUT" | sed -n '2p') # Second line is URL
        else
             # Ensure they are cleared if AWK_OUTPUT is empty to avoid using stale values from jq attempt
            ASSET_NAME=""
            DOWNLOAD_URL=""
        fi
    else
        echo_warning "'awk' not found. Cannot use 'awk' fallback."
    fi
fi


if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ] || [ -z "$ASSET_NAME" ]; then
    echo_error "Could not find download URL for a .deb package matching pattern '${MAGENTA}${DEB_NAME_REGEX_PATTERN}${RESET}'."
    echo_error "Neither 'jq' nor 'awk' fallback could determine the URL. Please check assets on GitHub Releases and their naming."
    exit 1
fi

echo_info "Found .deb package: ${MAGENTA}${ASSET_NAME}${RESET}"

TEMP_DIR=$(mktemp -d)
trap 'echo_info "Cleaning up temporary directory: ${TEMP_DIR}"; rm -rf "$TEMP_DIR"' EXIT

TEMP_DEB_PATH="${TEMP_DIR}/${ASSET_NAME}" # ASSET_NAME now reliably comes from jq or awk

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
    # Ensure apt lists are updated before trying to install a local deb that might have dependencies
    echo_info "Updating package lists (apt update)..."
    if ! apt update -qq; then # -qq for quieter output
        echo_warning "'apt update' failed. Proceeding with install attempt, but dependencies might not be found if lists are stale."
    fi

    if apt install -y "${TEMP_DEB_PATH}"; then
        echo_info "${GREEN}${BOLD}${DEB_NAME_PREFIX} installed successfully using apt!${RESET}"
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
            echo_warning "${YELLOW}${BOLD}${DEB_NAME_PREFIX} installed with dpkg.${RESET} Dependencies might be missing."
            if command -v apt >/dev/null 2>&1; then
                 echo_info "Please run ${MAGENTA}sudo apt --fix-broken install${RESET} to resolve any dependency issues."
            else
                echo_warning "Cannot advise 'apt --fix-broken install' as 'apt' is not available."
            fi
            INSTALL_SUCCESS=1 # Considered successful at dpkg level, user needs to fix deps
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
     echo_info "You should now be able to run the installed command, likely: ${MAGENTA}sudo shellswap${RESET}"
fi

exit 0
