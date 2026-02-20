#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="TeamTokenBar"
source "$ROOT/version.env"
DEFAULT_DMG_NAME="${APP_NAME}-${MARKETING_VERSION}.dmg"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ./Scripts/make_signed_dmg.sh [output-name.dmg]

Builds TeamTokenBar with Developer ID signing + notarization and produces a notarized DMG.
This wraps ./Scripts/sign-and-notarize.sh.

Options:
  output-name.dmg   Optional output DMG name. Defaults to TeamTokenBar-<version>.dmg

Environment:
  APP_STORE_CONNECT_API_KEY_P8
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  SPARKLE_PRIVATE_KEY_FILE
  ARCHES            Optional architectures override (example: "arm64 x86_64")
EOF
  exit 0
fi

TARGET_DMG_NAME="${1:-$DEFAULT_DMG_NAME}"
if [[ "$TARGET_DMG_NAME" != *.dmg ]]; then
  TARGET_DMG_NAME="${TARGET_DMG_NAME}.dmg"
fi

echo "==> Building signed/notarized release artifacts"
./Scripts/sign-and-notarize.sh

if [[ ! -f "$DEFAULT_DMG_NAME" ]]; then
  echo "ERROR: Expected DMG not found: $DEFAULT_DMG_NAME" >&2
  exit 1
fi

if [[ "$TARGET_DMG_NAME" != "$DEFAULT_DMG_NAME" ]]; then
  rm -f "$TARGET_DMG_NAME"
  mv "$DEFAULT_DMG_NAME" "$TARGET_DMG_NAME"
fi

echo "Done: $TARGET_DMG_NAME"
