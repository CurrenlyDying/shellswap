#!/bin/sh
# Script to download and install the latest shellswap binary from GitHub Releases.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="loputo"
REPO_NAME="shellswap"
BINARY_NAME="shellswap"
INSTALL_DIR="/bin"
GITHUB_API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

# --- Helper Functions ---
echo_info() {
    printf "\033[32m[INFO]\033[0m %s\n" "$1"
}

echo_error() {
    printf "\033[31m[ERROR]\033[0m %s\n" "$1" >&2
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
echo_info "Starting shellswap binary installation..."

# Check for root privileges (script is piped to sudo bash, but good check)
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

# Check for curl
if ! command -v curl >/dev/null 2>&1; then
    echo_error "curl is required but not installed. Please install curl."
    exit 1
fi

echo_info "Fetching latest release information for ${REPO_OWNER}/${REPO_NAME}..."
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
    echo_info "jq not available or failed to find asset. Trying grep/awk fallback..."
    # This grep/awk method is more fragile and depends on consistent JSON formatting from GitHub.
    # It looks for a line containing browser_download_url and the expected asset name, then extracts the URL.
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o "browser_download_url\": \"[^\"]*${EXPECTED_ASSET_NAME}\"" | awk -F'"' '{print $4}')
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_error "Could not find download URL for asset '${EXPECTED_ASSET_NAME}' for architecture '${ARCH}'."
    echo_error "Please check the GitHub Releases page for available assets."
    exit 1
fi

echo_info "Found download URL: ${DOWNLOAD_URL}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT # Ensure temporary directory is cleaned up

TEMP_BINARY_PATH="${TEMP_DIR}/${BINARY_NAME}"

echo_info "Downloading ${BINARY_NAME} to ${TEMP_BINARY_PATH}..."
if ! curl -LSs --fail -o "${TEMP_BINARY_PATH}" "${DOWNLOAD_URL}"; then
    echo_error "Failed to download binary from ${DOWNLOAD_URL}"
    exit 1
fi

echo_info "Verifying download..."
if [ ! -s "${TEMP_BINARY_PATH}" ]; then
    echo_error "Downloaded file is empty."
    exit 1
fi
chmod +x "${TEMP_BINARY_PATH}" # Make it executable to do a basic run test if desired, or just for install

echo_info "Installing ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}..."
if mv "${TEMP_BINARY_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"; then
    chown root:root "${INSTALL_DIR}/${BINARY_NAME}"
    chmod 755 "${INSTALL_DIR}/${BINARY_NAME}" # rwxr-xr-x
    echo_info "${BINARY_NAME} installed successfully to ${INSTALL_DIR}/${BINARY_NAME}"
    echo_info "You can now run it with 'sudo ${BINARY_NAME}'"
else
    echo_error "Failed to move binary to ${INSTALL_DIR}."
    # Attempt to clean up if mv failed but file might be there partially
    rm -f "${INSTALL_DIR}/${BINARY_NAME}" >/dev/null 2>&1
    exit 1
fi

exit 0
