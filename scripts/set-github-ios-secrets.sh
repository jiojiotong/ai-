#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  cat >&2 <<'EOF'
Usage:
  scripts/set-github-ios-secrets.sh OWNER/REPO

Example:
  scripts/set-github-ios-secrets.sh your-name/your-repo

Optional:
  IOS_CERTIFICATE_PASSWORD=... scripts/set-github-ios-secrets.sh your-name/your-repo

Required files:
  /Volumes/其他/Workspace/证书/证书文件(2).p12
  /Volumes/其他/Workspace/证书/描述文件(1).mobileprovision
EOF
  exit 1
fi

REPO="$1"
P12_PASSWORD="${IOS_CERTIFICATE_PASSWORD:-}"

if [ -z "$P12_PASSWORD" ]; then
  read -r -s -p "P12 password: " P12_PASSWORD
  printf '\n'
fi

CERT_PATH="/Volumes/其他/Workspace/证书/证书文件(2).p12"
PROFILE_PATH="/Volumes/其他/Workspace/证书/描述文件(1).mobileprovision"

if [ ! -f "$CERT_PATH" ]; then
  echo "Certificate not found: $CERT_PATH" >&2
  exit 1
fi

if [ ! -f "$PROFILE_PATH" ]; then
  echo "Provisioning profile not found: $PROFILE_PATH" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run gh auth login first." >&2
  exit 1
fi

PROFILE_PLIST="${TMPDIR:-/tmp}/ai-camera-profile.plist"
security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$PROFILE_PLIST")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' "$PROFILE_PLIST")
APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$PROFILE_PLIST")
BUNDLE_ID=${APP_IDENTIFIER#${TEAM_ID}.}

echo "Provisioning profile: $PROFILE_NAME"
echo "Team ID: $TEAM_ID"
echo "Bundle ID: $BUNDLE_ID"
echo "Repository: $REPO"

base64 -i "$CERT_PATH" | gh secret set IOS_CERTIFICATE_P12_BASE64 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set IOS_CERTIFICATE_PASSWORD --repo "$REPO"
base64 -i "$PROFILE_PATH" | gh secret set IOS_PROVISION_PROFILE_BASE64 --repo "$REPO"

echo "GitHub iOS signing secrets were set successfully."
