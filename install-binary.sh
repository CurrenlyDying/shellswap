#!/bin/sh
# Script to download and install the latest shellswap binary from GitHub Releases.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="CurrenlyDying"
REPO_NAME="shellswap"
BINARY_NAME="shellswap"
INSTALL_DIR="/bin"
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
    armv7l) ARCH="armhf" ;; # Example, adjust if you support armhf
    *)
        echo_error "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac
EXPECTED_ASSET_NAME="${BINARY_NAME}-${ARCH}"

# --- Main Script ---
echo_step "Starting shellswap binary installation"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

# Check for curl
if ! command -v curl >/dev/null 2>&1; then
    echo_error "'curl' is required but not installed. Please install curl."
    exit 1
fi

echo_info "Fetching latest release information for ${MAGENTA}${REPO_OWNER}/${REPO_NAME}${RESET}..."
# Fetch release info silently for parsing
RELEASE_INFO=$(curl -sSL "${GITHUB_API_URL}")

if [ -z "$RELEASE_INFO" ]; then
    echo_error "Failed to fetch release information. Check network or repository URL."
    exit 1
fi

DOWNLOAD_URL=""
# Try to parse with jq if available
if command -v jq >/dev/null 2>&1; then
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | jq -r ".assets[] | select(.name == \"${EXPECTED_ASSET_NAME}\") | .browser_download_url")
fi

# Fallback to grep/awk if jq failed or not available
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_warning "jq not available or failed to find asset using jq. Trying grep/awk fallback..."
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o "browser_download_url\": \"[^\"]*${EXPECTED_ASSET_NAME}\"" | awk -F'"' '{print $4}')
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_error "Could not find download URL for asset '${MAGENTA}${EXPECTED_ASSET_NAME}${RESET}' for architecture '${MAGENTA}${ARCH}${RESET}'."
    echo_error "Please check the GitHub Releases page for available assets."
    exit 1
fi

echo_info "Found download URL for ${MAGENTA}${EXPECTED_ASSET_NAME}${RESET}"

TEMP_DIR=$(mktemp -d)
trap 'echo_info "Cleaning up temporary directory: ${TEMP_DIR}"; rm -rf "$TEMP_DIR"' EXIT # Ensure temporary directory is cleaned up

TEMP_BINARY_PATH="${TEMP_DIR}/${BINARY_NAME}"

echo_step "Downloading ${BINARY_NAME} binary"
echo_info "URL: ${DOWNLOAD_URL}"
# Use --progress-bar for user feedback, -L to follow redirects, -f to fail on server errors
if ! curl -Lf --progress-bar -o "${TEMP_BINARY_PATH}" "${DOWNLOAD_URL}"; then
    echo_error "Failed to download binary from ${DOWNLOAD_URL}"
    exit 1
fi

echo_step "Verifying download"
if [ ! -s "${TEMP_BINARY_PATH}" ]; then
    echo_error "Downloaded file is empty."
    exit 1
fi
chmod +x "${TEMP_BINARY_PATH}"
echo_info "Download verified."

echo_step "Installing ${BINARY_NAME}"
echo_info "Moving binary to ${MAGENTA}${INSTALL_DIR}/${BINARY_NAME}${RESET}..."
if mv "${TEMP_BINARY_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"; then
    chown root:root "${INSTALL_DIR}/${BINARY_NAME}"
    chmod 755 "${INSTALL_DIR}/${BINARY_NAME}" # rwxr-xr-x
    echo_info "${GREEN}${BOLD}${BINARY_NAME} installed successfully!${RESET}"
    echo_info "You can now run it with: ${MAGENTA}sudo ${BINARY_NAME}${RESET}"
else
    echo_error "Failed to move binary to ${INSTALL_DIR}."
    rm -f "${INSTALL_DIR}/${BINARY_NAME}" >/dev/null 2>&1 # Attempt cleanup
    exit 1
fi

exit 0
