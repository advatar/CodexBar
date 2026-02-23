#!/usr/bin/env bash

# shellcheck shell=bash

sparkle_repo_slug() {
  local root_dir="${1:-$(pwd)}"
  local configured="${SPARKLE_GITHUB_REPO:-}"
  if [[ -n "$configured" ]]; then
    echo "$configured"
    return 0
  fi

  local remote_url repo_path owner repo
  remote_url=$(git -C "$root_dir" config --get remote.origin.url 2>/dev/null || true)
  if [[ -n "$remote_url" ]]; then
    if [[ "$remote_url" == *"://"* ]]; then
      repo_path="${remote_url#*://}"
      repo_path="${repo_path#*/}"
    elif [[ "$remote_url" == *:* ]]; then
      repo_path="${remote_url#*:}"
    else
      repo_path="$remote_url"
    fi

    repo_path="${repo_path#/}"
    repo_path="${repo_path%.git}"
    owner="${repo_path%%/*}"
    repo="${repo_path#*/}"
    repo="${repo%%/*}"

    if [[ -n "$owner" && -n "$repo" && "$owner" != "$repo_path" ]]; then
      echo "${owner}/${repo}"
      return 0
    fi
  fi

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "${GITHUB_REPOSITORY}"
    return 0
  fi

  echo "steipete/CodexBar"
}

sparkle_feed_url() {
  local root_dir="${1:-$(pwd)}"
  local repo_slug
  repo_slug=$(sparkle_repo_slug "$root_dir")
  echo "https://raw.githubusercontent.com/${repo_slug}/main/appcast.xml"
}

sparkle_release_download_prefix() {
  local root_dir="${1:-$(pwd)}"
  local version="${2:?version is required}"
  local repo_slug
  repo_slug=$(sparkle_repo_slug "$root_dir")
  echo "https://github.com/${repo_slug}/releases/download/v${version}/"
}
