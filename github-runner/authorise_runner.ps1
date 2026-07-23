#!/usr/bin/pwsh

# Check /pat file exists and is read-only
if (-not (Test-Path /pat)) {
    Write-Error "Error: /pat file not found. Ensure PAT is mounted."
    exit 1
}

$patItem = Get-Item /pat
if ($patItem.Attributes -band [IO.FileAttributes]::ReadOnly) {
    Write-Output "OK: /pat is read-only"
} else {
    Write-Warning "/pat is not read-only - ensure it is mounted read-only for security"
}

$PAT = Get-Content /pat

if (-not $env:GITHUB_ORG) {
    Write-Error "Error: GITHUB_ORG environment variable is required."
    exit 1
}
$GITHUB_ORG = $env:GITHUB_ORG

$URL="https://api.github.com/orgs/$($GITHUB_ORG)/actions/runners/registration-token"
$HEADERS=@{
    "Authorization"="token $($PAT)"
    "Accept"="application/vnd.github.v3+json"
}

$TOKEN = try {
    $response = Invoke-WebRequest -Uri $URL -Method POST -Headers $HEADERS
    ($response.content | ConvertFrom-Json).token
} catch {
    Write-Error "Failed to get registration token from GitHub API: $_"
    exit 1
}

if (-not $TOKEN) {
    Write-Error "Error: No registration token received"
    exit 1
}

# use hostname as the runner name
$name=uname -n

$CONFIG_URL="https://github.com/$($GITHUB_ORG)"

cd /actions-runner
write-output "Register Runner: $($name)"
/bin/sh -c "./config.sh --url $($CONFIG_URL) --unattended --replace --token $($TOKEN) --name $($name) --ephemeral --disableupdate"

### End of File
