#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! bash -lc '
  set -e
  source "'"$repo_root"'/scripts/codex-worktrees.zsh"
  if shopt -q nullglob; then
    echo "expected nullglob to start unset for this regression test" >&2
    exit 1
  fi

  if shopt -q nullglob; then
    _nullglob_restore="shopt -s nullglob"
  else
    _nullglob_restore="shopt -u nullglob"
  fi
  shopt -s nullglob
  env_sources=("'"$repo_root"'"/.env*)
  eval "$_nullglob_restore"
  ! shopt -q nullglob
'; then
  echo "expected bash nullglob restore flow to work with set -e" >&2
  exit 1
fi

echo "codex-worktrees nullglob restore works under bash with set -e"
