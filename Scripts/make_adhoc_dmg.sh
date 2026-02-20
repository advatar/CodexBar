#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="TeamTokenBar"
APP_BUNDLE="${APP_NAME}.app"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ./Scripts/make_adhoc_dmg.sh [output-name.dmg]

Builds TeamTokenBar.app with ad-hoc signing, then creates an ad-hoc signed DMG.

Options:
  output-name.dmg   Optional DMG filename. Defaults to TeamTokenBar-<version>-adhoc.dmg

Environment:
  SKIP_PACKAGE=1    Skip rebuilding the app and package the current TeamTokenBar.app
EOF
  exit 0
fi

if [[ "${SKIP_PACKAGE:-0}" != "1" ]]; then
  echo "==> Packaging app (release, ad-hoc signing)"
  CODEXBAR_SIGNING=adhoc ./Scripts/package_app.sh release
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: Missing $APP_BUNDLE. Run ./Scripts/package_app.sh first." >&2
  exit 1
fi

source "$ROOT/version.env"
DEFAULT_DMG_NAME="${APP_NAME}-${MARKETING_VERSION}-adhoc.dmg"
DMG_NAME="${1:-$DEFAULT_DMG_NAME}"

if [[ "$DMG_NAME" != *.dmg ]]; then
  DMG_NAME="${DMG_NAME}.dmg"
fi

echo "==> Creating DMG: $DMG_NAME"
STAGE_DIR="$(mktemp -d "/tmp/${APP_NAME}AdHocDMG.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

rm -f "$DMG_NAME"
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -ov \
  "$DMG_NAME"

echo "==> Applying ad-hoc signature to DMG"
codesign --force --sign - "$DMG_NAME"

echo "==> Verifying signature"
codesign -dv --verbose=2 "$DMG_NAME" 2>&1 | sed -n '1,10p'

echo "Done: $DMG_NAME"
