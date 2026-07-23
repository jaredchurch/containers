#!/bin/sh

set -e

echo "Install PowerShell"

# Get OS information
. /etc/os-release

# Check for supported distro
case "$ID" in
    ubuntu|debian)
        ;;
    *)
        echo "Error: Unsupported distro '$ID'. Only Ubuntu and Debian are supported."
        exit 1
        ;;
esac

# Download the Microsoft repository keys
MS_PKG_URL="https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb"
if ! wget -q "$MS_PKG_URL"; then
    echo "Error: Failed to download Microsoft packages from $MS_PKG_URL"
    echo "The URL may not exist for ${ID} ${VERSION_ID}"
    exit 1
fi

# Register the Microsoft repository keys
dpkg -i packages-microsoft-prod.deb

# Delete the Microsoft repository keys file
rm -f packages-microsoft-prod.deb

# Update the list of packages after we added packages.microsoft.com
apt-get update

###################################
# Install PowerShell
apt-get install -y powershell
pwsh --version

# Cleanup
rm -rf /var/lib/apt/lists/*

### End of File
