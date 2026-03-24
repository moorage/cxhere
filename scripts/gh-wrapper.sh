#!/usr/bin/env bash
set -euo pipefail

gh_config_dir="${GH_CONFIG_DIR:-/tmp/pulse-home/.config/gh}"

if ! mkdir -p "$gh_config_dir"; then
  echo "warning: failed to create gh config dir at $gh_config_dir" >&2
fi

export GH_CONFIG_DIR="$gh_config_dir"

exec /usr/local/bin/gh-real "$@"
