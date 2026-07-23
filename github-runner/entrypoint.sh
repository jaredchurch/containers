#!/bin/sh

set -ex

echo ""
echo ""
echo "####################### Starting Container #######################"
python3 --version

whoami
###################################

# Ownership
# echo "[$(date)]: Setting ownership of /actions-runner to ubuntu:ubuntu"
# chown -R ubuntu:ubuntu /actions-runner


# Start the listener, if this errors then register & try again (only known problem)
if [ ! -f ./.runner ]; then
    echo "[$(date)]: Register Runner"
    /usr/bin/pwsh -c /authorise_runner.ps1
else
    echo "[$(date)]: Runner already Registered"
fi


echo "[$(date)]: Start Listener..."
/actions-runner/run.sh


### End of File
