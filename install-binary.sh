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
    armv7l) ARCH="armhf" ;;
    *)
        echo_error "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac
EXPECTED_ASSET_NAME="${BINARY_NAME}-${ARCH}"

# --- Main Script ---
echo_step "Starting shellswap binary installation"

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

echo_info "Fetching latest release information for ${MAGENTA}${REPO_OWNER}/${REPO_NAME}${RESET}..."
RELEASE_INFO=$(curl -sSL "${GITHUB_API_URL}")

if [ -z "$RELEASE_INFO" ]; then
    echo_error "Failed to fetch release information. Check network or repository URL."
    exit 1
fi

DOWNLOAD_URL=""
if [ -n "$JQ_CMD" ]; then
    echo_info "Attempting to find asset URL using 'jq'..."
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | "$JQ_CMD" -r ".assets[] | select(.name == \"${EXPECTED_ASSET_NAME}\") | .browser_download_url")
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    if [ -n "$JQ_CMD" ]; then
        echo_warning "Failed to find asset using 'jq', or 'jq' is not installed/functional."
    else
        echo_warning "'jq' not found."
    fi

    if [ -n "$AWK_CMD" ]; then
        echo_info "Attempting to find asset URL using 'awk' fallback..."
        DOWNLOAD_URL=$(echo "$RELEASE_INFO" | "$AWK_CMD" -v asset_to_find="$EXPECTED_ASSET_NAME" '
            BEGIN { RS="},{" } # Split records by asset separator-ish
            /"name"[[:space:]]*:[[:space:]]*"'/ { # Basic check for a "name" field start
                current_name=""
                # Extract current asset name using match()
                if (match($0, /"name"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr_name)) {
                    current_name=arr_name[1]
                }

                if (current_name == asset_to_find) {
                    # If name matches, extract its browser_download_url
                    if (match($0, /"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr_url)) {
                        print arr_url[1]
                        exit # Found it
                    }
                }
            }
        ')
    else
        echo_warning "'awk' not found. Cannot use 'awk' fallback."
    fi
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_error "Could not find download URL for asset '${MAGENTA}${EXPECTED_ASSET_NAME}${RESET}' for architecture '${MAGENTA}${ARCH}${RESET}'."
    echo_error "Neither 'jq' nor 'awk' fallback could determine the URL. Please check assets on GitHub Releases."
    exit 1
fi

echo_info "Found download URL for ${MAGENTA}${EXPECTED_ASSET_NAME}${RESET}"

TEMP_DIR=$(mktemp -d)
trap 'echo_info "Cleaning up temporary directory: ${TEMP_DIR}"; rm -rf "$TEMP_DIR"' EXIT

TEMP_BINARY_PATH="${TEMP_DIR}/${BINARY_NAME}"

echo_step "Downloading ${BINARY_NAME} binary"
echo_info "URL: ${DOWNLOAD_URL}"
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
    chmod 755 "${INSTALL_DIR}/${BINARY_NAME}"
    echo_info "${GREEN}${BOLD}${BINARY_NAME} installed successfully!${RESET}"
    echo_info "You can now run it with: ${MAGENTA}sudo ${BINARY_NAME}${RESET}"
else
    echo_error "Failed to move binary to ${INSTALL_DIR}."
    rm -f "${INSTALL_DIR}/${BINARY_NAME}" >/dev/null 2>&1
    exit 1
fi

exit 0
