#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/lib/load-env.sh"
load_dotenv_if_present "$ROOT"

ACCOUNT=${SPARKLE_KEYCHAIN_ACCOUNT:-"codexbar-$(date -u +%Y%m%d%H%M%S)"}
PRIVATE_KEY_FILE=${1:-${SPARKLE_PRIVATE_KEY_FILE:-"$HOME/.config/codexbar/sparkle-private-key.txt"}}
FORCE=${FORCE:-0}

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ensure_parent_dir() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
}

upsert_unquoted_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp=$(mktemp)
  if [[ -f "$file" ]]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { done = 0 }
      $0 ~ "^[[:space:]]*" key "=" {
        print key "=" value
        done = 1
        next
      }
      { print }
      END {
        if (!done) {
          print key "=" value
        }
      }
    ' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  mv "$tmp" "$file"
}

upsert_quoted_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped="$value"
  local tmp

  escaped=${escaped//\\/\\\\}
  escaped=${escaped//\"/\\\"}

  tmp=$(mktemp)
  if [[ -f "$file" ]]; then
    awk -v key="$key" -v value="$escaped" '
      BEGIN { done = 0 }
      $0 ~ "^[[:space:]]*" key "=" {
        print key "=\"" value "\""
        done = 1
        next
      }
      { print }
      END {
        if (!done) {
          print key "=\"" value "\""
        }
      }
    ' "$file" > "$tmp"
  else
    printf '%s="%s"\n' "$key" "$escaped" > "$tmp"
  fi
  mv "$tmp" "$file"
}

find_generate_keys_tool() {
  if command -v generate_keys >/dev/null 2>&1; then
    command -v generate_keys
    return
  fi

  local project="$ROOT/.build/checkouts/Sparkle/Sparkle.xcodeproj"
  local derived_data="$ROOT/.build/sparkle-tools"
  local binary="$derived_data/Build/Products/Release/generate_keys"

  [[ -d "$project" ]] || fail "Sparkle source checkout not found at $project. Run swift build first."

  printf 'Building Sparkle generate_keys tool (one-time)...\n' >&2
  xcodebuild \
    -project "$project" \
    -scheme generate_keys \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    build >/dev/null

  [[ -x "$binary" ]] || fail "Failed to build generate_keys at $binary"
  printf '%s\n' "$binary"
}

validate_public_key() {
  local key="$1"
  [[ -n "$key" ]] || fail "Generated Sparkle public key is empty."
  [[ "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "Generated Sparkle public key is malformed: $key"
}

validate_private_key_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "Private key file was not written: $file"

  local key_lines
  key_lines=$(grep -v '^[[:space:]]*#' "$file" | sed '/^[[:space:]]*$/d')
  [[ $(printf "%s\n" "$key_lines" | wc -l) -eq 1 ]] || fail "Private key file must contain exactly one base64 line."

  local decoded_len
  decoded_len=$(python3 - <<PY
import base64
from pathlib import Path
line = "".join([ln.strip() for ln in Path("$file").read_text().splitlines() if ln.strip() and not ln.strip().startswith('#')])
raw = base64.b64decode(line)
print(len(raw))
PY
)
  [[ "$decoded_len" == "32" || "$decoded_len" == "96" ]] || fail "Unexpected decoded key length: $decoded_len bytes"
}

main() {
  local generator
  generator=$(find_generate_keys_tool)

  if "$generator" --account "$ACCOUNT" -p >/dev/null 2>&1; then
    fail "Keychain account '$ACCOUNT' already has a Sparkle key. Set SPARKLE_KEYCHAIN_ACCOUNT to a new value to rotate."
  fi

  if [[ -f "$PRIVATE_KEY_FILE" && "$FORCE" != "1" ]]; then
    fail "Private key file already exists at $PRIVATE_KEY_FILE (set FORCE=1 to overwrite)."
  fi

  ensure_parent_dir "$PRIVATE_KEY_FILE"

  log "Generating new Sparkle key under keychain account: $ACCOUNT"
  "$generator" --account "$ACCOUNT" >/dev/null

  local public_key
  public_key=$(
    "$generator" --account "$ACCOUNT" -p \
      | tr -d '\r' \
      | tail -n1 \
      | tr -d '[:space:]'
  )
  validate_public_key "$public_key"

  log "Exporting private key to: $PRIVATE_KEY_FILE"
  rm -f "$PRIVATE_KEY_FILE"
  "$generator" --account "$ACCOUNT" -x "$PRIVATE_KEY_FILE"
  validate_private_key_file "$PRIVATE_KEY_FILE"

  upsert_unquoted_var "$ROOT/version.env" "SPARKLE_PUBLIC_ED_KEY" "$public_key"

  upsert_quoted_var "$ROOT/.env" "SPARKLE_PRIVATE_KEY_FILE" "$PRIVATE_KEY_FILE"
  upsert_quoted_var "$ROOT/.env" "SPARKLE_PUBLIC_ED_KEY" "$public_key"
  upsert_quoted_var "$ROOT/.env" "SPARKLE_KEYCHAIN_ACCOUNT" "$ACCOUNT"

  log "Rotated Sparkle key successfully."
  log "New SUPublicEDKey: $public_key"
  log "Updated files: $ROOT/version.env and $ROOT/.env"
}

main "$@"
