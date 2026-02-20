#!/usr/bin/env bash

# shellcheck shell=bash

load_dotenv_if_present() {
  local root_dir="${1:-$(pwd)}"
  local dotenv_file="${root_dir}/.env"

  if [[ ! -f "${dotenv_file}" ]]; then
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "${dotenv_file}"
  set +a
}
