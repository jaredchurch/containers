#!/bin/sh

# GitHub Actions Self-Hosted Runner - Entrypoint Script
# Handles runner registration and startup

set -ex

# Validates that required files and environment variables are present
check_prerequisites() {
    # Check PAT file exists
    if [ ! -f /pat ]; then
        echo "Error: /pat file not found. Ensure PAT is mounted."
        exit 1
    fi

    # Check PAT file is readable
    if [ ! -r /pat ]; then
        echo "Warning: /pat is not readable"
        exit 1
    fi

    # Test if mounted read-only by attempting touch
    if touch /pat 2>/dev/null; then
        echo "Warning: /pat is writable - ensure it is mounted read-only for security"
    else
        echo "OK: /pat is read-only"
    fi

    # Check GITHUB_ORG is set
    if [ -z "$GITHUB_ORG" ]; then
        echo "Error: GITHUB_ORG environment variable is required."
        exit 1
    fi
}

# Registers the runner with GitHub and configures it
register_runner() {
    # Read PAT and construct API request
    PAT=$(cat /pat)
    URL="https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/registration-token"

    # Request registration token from GitHub API
    TOKEN=$(curl -s -X POST \
        -H "Authorization: token ${PAT}" \
        -H "Accept: application/vnd.github.v3+json" \
        "$URL" | jq -r '.token')

    # Validate token was received
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "Error: Failed to get registration token from GitHub API"
        exit 1
    fi

    # Get runner name from hostname and configure runner
    RUNNER_NAME=${HOSTNAME}
    CONFIG_URL="https://github.com/${GITHUB_ORG}"

    echo "[$(date)]: Registering runner: ${RUNNER_NAME}"
    cd /actions-runner
    ./config.sh --url "$CONFIG_URL" --unattended --replace --token "$TOKEN" --name "$RUNNER_NAME" --ephemeral --disableupdate
}

# Main entrypoint logic
main() {
    echo ""
    echo ""
    echo "####################### Starting Container #######################"
    python3 --version
    whoami

    # Validate prerequisites
    check_prerequisites

    # Register runner if not already registered
    if [ ! -f ./.runner ]; then
        echo "[$(date)]: Register Runner"
        register_runner
    else
        echo "[$(date)]: Runner already Registered"
    fi

    # Start the runner listener
    echo "[$(date)]: Start Listener..."
    /actions-runner/run.sh
}

# Execute main function
main "$@"

### End of File
