#!/bin/bash
set -e

# export DEBIAN_FRONTEND=noninteractive

# install bitwarden cli
if [ "$(which bws)" != "" ] ; then
  echo "Bitwarden CLI already installed"
else
  echo "Installing Bitwarden Secrets Manager CLI..."
  curl https://bws.bitwarden.com/install | sh
fi


URL="https://vault.bitwarden.com/download/?app=cli&platform=linux"

# Set up some directories to avoid warnings
mkdir -p "$HOME/.config/Bitwarden CLI"
touch "$HOME/.config/Bitwarden CLI/data.json"

if [ ! -f /usr/local/bin/bw ]; then
    echo "Download BitWarden Zip"
    wget "$URL" --quiet -O /tmp/bw.zip

    echo "Install BitWarden"
    unzip /tmp/bw.zip
    sudo mv -f ./bw /usr/local/bin/bw

    echo "Clean Up BitWarden Install"
    rm -f /tmp/bw.zip
fi

echo "✅ Install Bitwarden Secrets Manager"

### End of File
