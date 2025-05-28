#!/bin/sh
# Script to download and install the latest shellswap .deb package from GitHub Releases.

# Exit on error, treat unset variables as an error, and ensure pipe failures are caught.
set -euo pipefail

# --- Configuration ---
REPO_OWNER="loputo"
REPO_NAME="shellswap"
DEB_NAME_PREFIX="shellswap" # Assuming .deb files start with "shellswap"
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
    armv7l) ARCH="armhf" ;;
    *)
        echo_error "Unsupported architecture for .deb: $(uname -m)"
        exit 1
        ;;
esac
# Example: shellswap_1.0-1_amd64.deb. We need to match this pattern.
EXPECTED_DEB_PATTERN_SUFFIX="_${ARCH}.deb"

# --- Main Script ---
echo_info "Starting shellswap .deb package installation..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root. Please use 'sudo'."
    exit 1
fi

# Check for curl and apt
if ! command -v curl >/dev/null 2>&1; then
    echo_error "curl is required but not installed. Please install curl."
    exit 1
fi
if ! command -v apt >/dev/null 2>&1; then
    echo_error "apt is required but not installed. This script is for Debian-based systems."
    exit 1
fi

echo_info "Fetching latest release information for ${REPO_OWNER}/${REPO_NAME}..."
RELEASE_INFO=$(curl -sSL "${GITHUB_API_URL}")

if [ -z "$RELEASE_INFO" ]; then
    echo_error "Failed to fetch release information. Check network or repository URL."
    exit 1
fi

DOWNLOAD_URL=""
ASSET_NAME=""

# Try to parse with jq if available
if command -v jq >/dev/null 2>&1; then
    # Selects assets that start with DEB_NAME_PREFIX and end with EXPECTED_DEB_PATTERN_SUFFIX
    ASSET_INFO=$(echo "$RELEASE_INFO" | jq -r ".assets[] | select(.name | startswith(\"${DEB_NAME_PREFIX}\") and endswith(\"${EXPECTED_DEB_PATTERN_SUFFIX}\"))")
    if [ -n "$ASSET_INFO" ]; then
        DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url' | head -n 1) # Take first match
        ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name' | head -n 1)
    fi
fi

# Fallback to grep/awk if jq failed or not available
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo_info "jq not available or failed to find .deb asset. Trying grep/awk fallback..."
    # This looks for a .deb file for the specific architecture.
    # It's more complex and fragile than the binary one due to versioning in the name.
    # This simplistic grep might pick up other .deb files if names are not unique enough.
    # It tries to find a line with browser_download_url containing the prefix and suffix.
    LINE_WITH_URL=$(echo "$RELEASE_INFO" | grep "browser_download_url\"" | grep "${DEB_NAME_PREFIX}" | grep "${EXPECTED_DEB_PATTERN_SUFFIX}")
    if [ -n "$LINE_WITH_URL" ]; then
         # Extract name: "name": "shellswap_1.2.3_amd64.deb",
        ASSET_NAME=$(echo "$LINE_WITH_URL" | sed -n 's/.*"name": "\(.*'"${DEB_NAME_PREFIX}"'.*'"${EXPECTED_DEB_PATTERN_SUFFIX}"'\)".*/\1/p' | head -n 1)
        # Extract URL: "browser_download_url": "https://...",
        DOWNLOAD_URL=$(echo "$LINE_WITH_URL" | sed -n 's/.*"browser_download_url": "\(https:[^"]*'"${ASSET_NAME}"'\)".*/\1/p' | head -n 1)
        # A simpler sed if asset name is unique in the download URL:
        # DOWNLOAD_URL=$(echo "$LINE_WITH_URL" | sed -n 's/.*"browser_download_url": "\(https:[^"]*\)".*/\1/p' | head -n 1)
        # This fallback is very basic. If asset names are like shellswap_VERSION_ARCH.deb:
        if [ -z "$ASSET_NAME" ] || [ -z "$DOWNLOAD_URL" ]; then # Try another grep if the above was too specific
            MATCHING_ASSET_LINE=$(echo "$RELEASE_INFO" | grep -Eio "\"browser_download_url\": \"[^\"]*${DEB_NAME_PREFIX}[^\"]*${EXPECTED_DEB_PATTERN_SUFFIX}\"" | head -n 1)
            if [ -n "$MATCHING_ASSET_LINE" ]; then
                DOWNLOAD_URL=$(echo "$MATCHING_ASSET_LINE" | awk -F'"' '{print $4}')
                # Try to get asset name from URL (basename)
                ASSET_NAME=$(basename "$DOWNLOAD_URL")
            fi
        fi
    fi
fi


if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ] || [ -z "$ASSET_NAME" ]; then
    echo_error "Could not find download URL for a .deb package matching pattern '${DEB_NAME_PREFIX}...${EXPECTED_DEB_PATTERN_SUFFIX}'."
    echo_error "Please check the GitHub Releases page for available assets."
    exit 1
fi

echo_info "Found .deb package: ${ASSET_NAME}"
echo_info "Download URL: ${DOWNLOAD_URL}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

TEMP_DEB_PATH="${TEMP_DIR}/${ASSET_NAME}"

echo_info "Downloading ${ASSET_NAME} to ${TEMP_DEB_PATH}..."
if ! curl -LSs --fail -o "${TEMP_DEB_PATH}" "${DOWNLOAD_URL}"; then
    echo_error "Failed to download .deb package from ${DOWNLOAD_URL}"
    exit 1
fi

echo_info "Verifying download..."
if [ ! -s "${TEMP_DEB_PATH}" ]; then
    echo_error "Downloaded file is empty."
    exit 1
fi

echo_info "Updating package list (apt update)..."
if ! apt update -qq; then
    echo_error "apt update failed. Please check your internet connection and apt sources."
    # Proceeding with install anyway, apt install might handle it or fail more clearly.
fi

echo_info "Installing .deb package with apt..."
# Using apt install ./file.deb is preferred as it handles dependencies.
if apt install -y "${TEMP_DEB_PATH}"; then
    echo_info "${DEB_NAME_PREFIX} installed successfully from .deb package!"
    echo_info "You can now run it with 'sudo ${BINARY_NAME:-shellswap}'" # BINARY_NAME is not defined here, use shellswap or derive.
else
    echo_error "Failed to install .deb package."
    echo_error "You might need to resolve dependencies manually or check 'apt' output."
    exit 1
fi

exit 0
