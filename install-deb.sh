#!/bin/sh
# Script to download and install the latest shellswap .deb package from GitHub Releases.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="loputo"
REPO_NAME="shellswap"
DEB_NAME_PREFIX="shellswap" # Assuming .deb files start with "shellswap"
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
    # $1: Color, $2: Level String
    printf "%s%s%s%s " "$1" "$BOLD" "[$2]" "$RESET"
}
echo_step() {
    # $1: Message
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

# --- Main Script ---
echo_step "Starting shellswap .deb package installation"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

# Check for curl, apt, and dpkg
if ! command -v curl >/dev/null 2>&1; then
    echo_error "'curl' is required but not installed. Please install curl."
    exit 1
fi
if ! command -v apt >/dev/null 2>&1; then
    echo_warning "'apt' command not found. Installation might be limited."
    # Allow to proceed, dpkg might still work
fi
if ! command -v dpkg >/dev/null 2>&1; then
    echo_error "'dpkg' command not found. Cannot install .deb package."
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

# Try to parse with jq if available
if command -v jq >/dev/null 2>&1; then
    ASSET_INFO=$(echo "$RELEASE_INFO" | jq -r ".assets[] | select(.name | startswith(\"${DEB_NAME_PREFIX}\") and endswith(\"${EXPECTED_DEB_PATTERN_SUFFIX}\"))")
    if [ -n "$ASSET_INFO" ] && [ "$ASSET_INFO" != "null" ]; then
        DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url' | head -n 1)
        ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name' | head -n 1)
    fi
fi

# Fallback to grep/awk if jq failed or not available
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_warning "jq not available or failed to find .deb asset using jq. Trying grep/awk fallback..."
    MATCHING_ASSET_LINE=$(echo "$RELEASE_INFO" | grep -Eio "\"name\": \"(${DEB_NAME_PREFIX}[^\"]*${EXPECTED_DEB_PATTERN_SUFFIX})\"[^\}]*\"browser_download_url\": \"([^\"]*)\"" | head -n 1)
    if [ -n "$MATCHING_ASSET_LINE" ]; then
         # Using a more robust sed to capture name and URL if both are on the same "asset block" context
         # This regex is an example and might need adjustment based on actual GitHub API JSON snippet structure
        ASSET_NAME=$(echo "$MATCHING_ASSET_LINE" | sed -n 's/.*"name": "\([^"]*\)".*/\1/p')
        DOWNLOAD_URL=$(echo "$MATCHING_ASSET_LINE" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p')

        # Basic check if extracted name truly matches pattern (sed might be too greedy)
        if ! echo "$ASSET_NAME" | grep -qE "^${DEB_NAME_PREFIX}.*${EXPECTED_DEB_PATTERN_SUFFIX}$"; then
            ASSET_NAME="" # Invalidate if name doesn't fit
            DOWNLOAD_URL=""
        fi
    fi
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ] || [ -z "$ASSET_NAME" ]; then
    echo_error "Could not find download URL for a .deb package matching pattern '${MAGENTA}${DEB_NAME_PREFIX}...${EXPECTED_DEB_PATTERN_SUFFIX}${RESET}'."
    echo_error "Please check the GitHub Releases page for available assets and naming."
    exit 1
fi

echo_info "Found .deb package: ${MAGENTA}${ASSET_NAME}${RESET}"

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
    echo_info "Attempting installation with 'dpkg -i'..."
    if dpkg -i "${TEMP_DEB_PATH}"; then
        echo_warning "${YELLOW}${BOLD}${DEB_NAME_PREFIX} installed with dpkg.${RESET} Dependencies might be missing."
        echo_info "Please run ${MAGENTA}sudo apt --fix-broken install${RESET} to resolve any dependency issues."
        INSTALL_SUCCESS=1 # Considered successful at dpkg level, user needs to fix deps
    else
        echo_error "'dpkg -i' also failed."
        echo_error "Failed to install .deb package. Please check the output for errors."
        exit 1
    fi
fi

if [ "$INSTALL_SUCCESS" -eq 1 ]; then
     echo_info "You should now be able to run the installed command, likely: ${MAGENTA}sudo shellswap${RESET}"
fi

exit 0
