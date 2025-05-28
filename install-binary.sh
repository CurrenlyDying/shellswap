#!/bin/sh
# Script to download and install the latest shellswap binary from GitHub Releases.
# Simplified to use only curl, grep, and sed for release parsing.
# Colors fixed using printf %b.

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
    armv7l) ARCH="armhf" ;; # Example, adjust if you support armhf
    *)
        echo_error "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac
EXPECTED_ASSET_NAME="${BINARY_NAME}-${ARCH}" # e.g., shellswap-amd64

# --- Main Script ---
echo_step "Starting shellswap binary installation"

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

echo_info "Fetching latest release information for ${MAGENTA}${REPO_OWNER}/${REPO_NAME}${RESET}..."
RELEASE_INFO=$(curl -sSL "${GITHUB_API_URL}")

if [ -z "$RELEASE_INFO" ]; then
    echo_error "Failed to fetch release information. Check network or repository URL."
    exit 1
fi

DOWNLOAD_URL=""
echo_info "Attempting to find asset URL using 'grep' and 'sed'..."

DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -Eo "\"browser_download_url\": \"[^\"]*${EXPECTED_ASSET_NAME}\"" | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo_warning "First attempt to find URL failed. Trying broader search for asset: ${EXPECTED_ASSET_NAME}"
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -Eo "\"browser_download_url\": \"[^\"]*\"" | grep "${EXPECTED_ASSET_NAME}" | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' | head -n 1)
fi


if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    # Use printf %b for MAGENTA and RESET here
    printf "%bCould not find download URL for asset '%b%s%b' for architecture '%b%s%b'.%b\n" \
        "$(_log_prefix "$RED" "ERROR")" \
        "$MAGENTA" "$EXPECTED_ASSET_NAME" "$RESET" \
        "$MAGENTA" "$ARCH" "$RESET" \
        "$RESET" >&2
    echo_error "Please check assets on GitHub Releases. The script uses 'grep' and 'sed' for parsing."
    exit 1
fi

# Use printf %b for MAGENTA and RESET here
printf "%sFound download URL for %b%s%b\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "$EXPECTED_ASSET_NAME" "$RESET"


TEMP_DIR=$(mktemp -d)
# Use printf %b for MAGENTA and RESET in trap message
trap 'printf "%sCleaning up temporary directory: %b%s%b\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "$TEMP_DIR" "$RESET"; rm -rf "$TEMP_DIR"' EXIT

TEMP_BINARY_PATH="${TEMP_DIR}/${BINARY_NAME}"

echo_step "Downloading ${BINARY_NAME} binary"
echo_info "URL: ${DOWNLOAD_URL}" # DOWNLOAD_URL is plain text
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
# Use printf %b for MAGENTA and RESET here
printf "%sMoving binary to %b%s/%s%b...\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "$INSTALL_DIR" "$BINARY_NAME" "$RESET"

if mv "${TEMP_BINARY_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"; then
    chown root:root "${INSTALL_DIR}/${BINARY_NAME}"
    chmod 755 "${INSTALL_DIR}/${BINARY_NAME}"
    # Use printf %b for GREEN, BOLD, RESET here
    printf "%s%b%b%s installed successfully!%b\n" "$(_log_prefix "$GREEN" "INFO")" "$GREEN" "$BOLD" "$BINARY_NAME" "$RESET"
    # Use printf %b for MAGENTA and RESET here
    printf "%sYou can now run it with: %b%s %s%b\n" "$(_log_prefix "$GREEN" "INFO")" "$MAGENTA" "sudo" "$BINARY_NAME" "$RESET"
else
    echo_error "Failed to move binary to ${INSTALL_DIR}."
    rm -f "${INSTALL_DIR}/${BINARY_NAME}" >/dev/null 2>&1
    exit 1
fi

exit 0
