#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="TeamTokenBar"
source "$ROOT/version.env"
source "$ROOT/Scripts/lib/github-defaults.sh"

PIGGYBANK_FILE="${PIGGYBANK_FILE:-$ROOT/thepiggybank/src/pages/Index.tsx}"
DMG_NAME="${APP_NAME}-${MARKETING_VERSION}.dmg"
DOWNLOAD_URL="$(sparkle_release_download_prefix "$ROOT" "$MARKETING_VERSION")${DMG_NAME}"

if [[ ! -f "$PIGGYBANK_FILE" ]]; then
  echo "ERROR: thepiggybank download page not found: $PIGGYBANK_FILE" >&2
  exit 1
fi

HREF_COUNT=$(rg -o 'href="[^"]*\.dmg"' "$PIGGYBANK_FILE" | wc -l | tr -d ' ')
if [[ "$HREF_COUNT" != "1" ]]; then
  echo "ERROR: Expected exactly one DMG href in $PIGGYBANK_FILE, found $HREF_COUNT" >&2
  exit 1
fi

CURRENT_HREF=$(rg -o 'href="[^"]*\.dmg"' "$PIGGYBANK_FILE")
TARGET_HREF="href=\"$DOWNLOAD_URL\""

if [[ "$CURRENT_HREF" == "$TARGET_HREF" ]]; then
  echo "thepiggybank download URL already up to date:"
  echo "  $DOWNLOAD_URL"
  exit 0
fi

perl -0pi -e 's|href="[^"]*\.dmg"|href="'"$DOWNLOAD_URL"'"|' "$PIGGYBANK_FILE"

if ! rg -q "href=\"$DOWNLOAD_URL\"" "$PIGGYBANK_FILE"; then
  echo "ERROR: Failed to update download URL in $PIGGYBANK_FILE" >&2
  exit 1
fi

echo "Updated thepiggybank download URL:"
echo "  $DOWNLOAD_URL"
