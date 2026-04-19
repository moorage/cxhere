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

if ! bash -lc '
  set -euo pipefail
  repo_root="'"$repo_root"'"
  tmpdir="$(mktemp -d)"
  trap '\''rm -rf "$tmpdir"'\'' EXIT

  export HOME="$tmpdir/home"
  mkdir -p "$HOME"
  mkdir -p "$HOME/.codex" "$tmpdir/bin"
  PATH="$tmpdir/bin:$PATH"
  export PATH
  cat > "$tmpdir/bin/codex" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/codex"
  cat > "$HOME/.codex/AGENTS.md" <<'\''EOF'\''
# test
EOF
  cat > "$HOME/.codex/config.toml" <<'\''EOF'\''
[projects."/workspace"]
trust_level = "trusted"
EOF

  source "$repo_root/scripts/codex-worktrees.zsh"

  git init "$tmpdir/repo" >/dev/null
  git -C "$tmpdir/repo" config user.name "Test User"
  git -C "$tmpdir/repo" config user.email "test@example.com"
  printf "seed\n" > "$tmpdir/repo/README.md"
  git -C "$tmpdir/repo" add README.md
  git -C "$tmpdir/repo" commit -m init >/dev/null

  worktree_dir="$tmpdir/repo-worktrees/list"
  git -C "$tmpdir/repo" worktree add -b list "$worktree_dir" >/dev/null
  rm -rf "$worktree_dir"

  names_output="$(cd "$tmpdir/repo" && cx_worktree_names)"
  if [ -n "$names_output" ]; then
    echo "expected stale prunable worktrees to be pruned before completion output" >&2
    exit 1
  fi

  close_output="$(cd "$tmpdir/repo" && cxclose list 2>&1 || true)"
  if printf "%s\n" "$close_output" | rg -F "fatal: cannot change to" >/dev/null; then
    echo "expected cxclose to avoid git fatal errors for pruned worktrees" >&2
    exit 1
  fi
  if ! printf "%s\n" "$close_output" | rg -F "worktree not found for: list" >/dev/null; then
    echo "expected cxclose to report the pruned stale worktree" >&2
    exit 1
  fi

  list_output="$(cd "$tmpdir/repo" && cxlist)"
  if ! printf "%s\n" "$list_output" | rg -F "no active codex worktrees." >/dev/null; then
    echo "expected cxlist to hide pruned stale worktrees" >&2
    exit 1
  fi

  here_output="$(cd "$tmpdir/repo" && printf "\n\n\n" | CXHERE_RUNTIME=local cxhere list 2>&1)"
  if printf "%s\n" "$here_output" | rg -F "worktree directory exists but is not registered" >/dev/null; then
    echo "expected cxhere to prune stale worktree metadata before recreating the worktree" >&2
    exit 1
  fi
  if [ ! -d "$worktree_dir" ]; then
    echo "expected cxhere to recreate the pruned worktree directory" >&2
    exit 1
  fi
'; then
  echo "expected stale codex worktrees to be pruned before completion, listing, and close" >&2
  exit 1
fi

echo "stale codex worktrees are pruned before completion, listing, and close"
