#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

TAG=${1:-$(git describe --tags --abbrev=0)}
ARTIFACT_PREFIX="TeamTokenBar-"

check_assets "$TAG" "$ARTIFACT_PREFIX"

DMG_PATTERN="^${ARTIFACT_PREFIX}[0-9][0-9A-Za-z.+_-]*\\.dmg$"
if ! gh release view "$TAG" --json assets --jq '.assets[].name' | grep -Eq "$DMG_PATTERN"; then
  echo "ERROR: missing DMG asset for ${TAG} (expected ${ARTIFACT_PREFIX}<version>.dmg)." >&2
  exit 1
fi
