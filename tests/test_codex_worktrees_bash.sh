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

if ! bash -lc '
  set -euo pipefail
  repo_root="'"$repo_root"'"
  tmpdir="$(mktemp -d)"
  trap '\''rm -rf "$tmpdir"'\'' EXIT

  mkdir -p "$tmpdir/bin" "$tmpdir/harness/new-codex-project-harness-main/docs" "$tmpdir/project"
  PATH="$tmpdir/bin:$PATH"
  export PATH

  cat > "$tmpdir/bin/curl" <<'\''EOF'\''
#!/usr/bin/env bash
cat "$CXHERE_TEST_HARNESS_TARBALL"
EOF
  chmod +x "$tmpdir/bin/curl"

  printf "harness\n" > "$tmpdir/harness/new-codex-project-harness-main/README.md"
  printf "plan\n" > "$tmpdir/harness/new-codex-project-harness-main/docs/PLANS.md"
  tar -czf "$tmpdir/harness.tar.gz" -C "$tmpdir/harness" new-codex-project-harness-main
  export CXHERE_TEST_HARNESS_TARBALL="$tmpdir/harness.tar.gz"
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"
  project_dir="$(cd "$tmpdir/project" && pwd -P)"

  source "$repo_root/scripts/codex-worktrees.zsh"
  cx_command_prelude() { :; }

  output="$(cd "$tmpdir/project" && printf "y\ny\n\n" | cxharness 2>&1)"
  if ! printf "%s\n" "$output" | rg -F "Run git init in the current directory before importing the harness?" >/dev/null; then
    echo "expected cxharness to prompt before initializing a new git repo" >&2
    exit 1
  fi
  if ! printf "%s\n" "$output" | rg -F "initialized git repo in $project_dir" >/dev/null; then
    echo "expected cxharness to initialize a git repo before copying harness files" >&2
    exit 1
  fi
  if ! git -C "$project_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "expected cxharness to leave the destination as a git repo" >&2
    exit 1
  fi
  if [ ! -f "$project_dir/README.md" ] || [ ! -f "$project_dir/docs/PLANS.md" ]; then
    echo "expected cxharness to copy the harness files after git init" >&2
    exit 1
  fi
  if ! printf "%s\n" "$output" | rg -F "Create a git commit for the downloaded harness files with message \"cxharness\"? [Y/n]" >/dev/null; then
    echo "expected cxharness to offer a final default-yes git commit prompt" >&2
    exit 1
  fi
  if [ "$(git -C "$project_dir" log -1 --pretty=%s)" != "cxharness" ]; then
    echo "expected cxharness to create a commit with the cxharness message when the final prompt defaults to yes" >&2
    exit 1
  fi
'; then
  echo "expected cxharness to initialize a git repo before copying into a non-repo directory" >&2
  exit 1
fi

echo "cxharness initializes a git repo before copying into a non-repo directory"

if ! bash -lc '
  set -euo pipefail
  repo_root="'"$repo_root"'"
  tmpdir="$(mktemp -d)"
  trap '\''rm -rf "$tmpdir"'\'' EXIT

  export HOME="$tmpdir/home"
  mkdir -p "$HOME/.codex" "$tmpdir/bin"
  PATH="$tmpdir/bin:$PATH"
  export PATH

  cat > "$tmpdir/bin/docker" <<'\''EOF'\''
#!/usr/bin/env bash
printf "%s\n" "$@" > "$CXHERE_TEST_DOCKER_ARGS_FILE"
EOF
  cat > "$tmpdir/bin/container" <<'\''EOF'\''
#!/usr/bin/env bash
printf "%s\n" "$@" > "$CXHERE_TEST_CONTAINER_ARGS_FILE"
EOF
  chmod +x "$tmpdir/bin/docker" "$tmpdir/bin/container"

  cat > "$HOME/.codex/AGENTS.md" <<'\''EOF'\''
# test
EOF
  cat > "$HOME/.codex/config.toml" <<'\''EOF'\''
[projects."/workspace"]
trust_level = "trusted"
EOF
  cat > "$HOME/.gitconfig" <<'\''EOF'\''
[user]
  name = Test User
  email = test@example.com
EOF

  source "$repo_root/scripts/codex-worktrees.zsh"
  cx_command_prelude() { :; }
  cx_require_runtime() { :; }
  cx_require_local_image() { :; }
  cx_runtime_ready_silent() { return 1; }
  cx_list_worktree_containers() { return 0; }

  git init "$tmpdir/repo" >/dev/null
  git -C "$tmpdir/repo" config user.name "Test User"
  git -C "$tmpdir/repo" config user.email "test@example.com"
  mkdir -p "$tmpdir/repo/docs"
  printf "seed\n" > "$tmpdir/repo/README.md"
  printf "plan\n" > "$tmpdir/repo/docs/PLANS.md"
  printf ".pw-browsers\nseccomp_profile.json\n.env*\n" > "$tmpdir/repo/.gitignore"
  git -C "$tmpdir/repo" add README.md docs/PLANS.md .gitignore
  git -C "$tmpdir/repo" commit -m init >/dev/null
  printf "PORT=5173\n" > "$tmpdir/repo/.env.cx.local"

  export CXHERE_TEST_DOCKER_ARGS_FILE="$tmpdir/docker.args"
  set +u
  docker_output="$(cd "$tmpdir/repo" && CXHERE_RUNTIME=docker cxhere -p 5173 -p 5174:5714/udp test/docker 2>&1)"
  set -u
  if ! printf "%s\n" "$docker_output" | rg -F "worktree directory:" >/dev/null; then
    echo "expected docker cxhere invocation to complete" >&2
    exit 1
  fi
  if ! rg -F -x -- "--publish" "$CXHERE_TEST_DOCKER_ARGS_FILE" >/dev/null; then
    echo "expected docker run invocation to include --publish" >&2
    exit 1
  fi
  if ! rg -F -x "127.0.0.1:5173:5173/tcp" "$CXHERE_TEST_DOCKER_ARGS_FILE" >/dev/null; then
    echo "expected docker run invocation to publish host 5173 to container 5173" >&2
    exit 1
  fi
  if ! rg -F -x "127.0.0.1:5174:5714/udp" "$CXHERE_TEST_DOCKER_ARGS_FILE" >/dev/null; then
    echo "expected docker run invocation to publish host 5174 to container 5714/udp" >&2
    exit 1
  fi

  export CXHERE_TEST_CONTAINER_ARGS_FILE="$tmpdir/container.args"
  set +u
  container_output="$(cd "$tmpdir/repo" && CXHERE_RUNTIME=container cxhere --port 5173:5713 test/container 2>&1)"
  set -u
  if ! printf "%s\n" "$container_output" | rg -F "worktree directory:" >/dev/null; then
    echo "expected Apple container cxhere invocation to complete" >&2
    exit 1
  fi
  if ! rg -F -x -- "--publish" "$CXHERE_TEST_CONTAINER_ARGS_FILE" >/dev/null; then
    echo "expected container run invocation to include --publish" >&2
    exit 1
  fi
  if ! rg -F -x "127.0.0.1:5173:5713/tcp" "$CXHERE_TEST_CONTAINER_ARGS_FILE" >/dev/null; then
    echo "expected container run invocation to publish host 5173 to container 5713" >&2
    exit 1
  fi

  set +eu
  local_output="$(cd "$tmpdir/repo" && CXHERE_RUNTIME=local cxhere -p 5173 test/local 2>&1)"
  local_status=$?
  set -euo pipefail
  if [ "$local_status" -eq 0 ]; then
    echo "expected local cxhere invocation with -p to fail" >&2
    exit 1
  fi
  if ! printf "%s\n" "$local_output" | rg -F "cxhere: -p/--port requires CXHERE_RUNTIME=container or docker" >/dev/null; then
    echo "expected local cxhere invocation to explain the unsupported -p flag" >&2
    exit 1
  fi
'; then
  echo "expected cxhere -p to publish localhost ports for Docker and Apple container runtimes" >&2
  exit 1
fi

echo "cxhere -p publishes localhost ports for Docker and Apple container runtimes"

if ! bash -lc '
  set -euo pipefail
  repo_root="'"$repo_root"'"
  tmpdir="$(mktemp -d)"
  trap '\''rm -rf "$tmpdir"'\'' EXIT

  export HOME="$tmpdir/home"
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
  cx_command_prelude() { :; }

  git init "$tmpdir/repo" >/dev/null
  git -C "$tmpdir/repo" config user.name "Test User"
  git -C "$tmpdir/repo" config user.email "test@example.com"
  mkdir -p "$tmpdir/repo/docs" "$tmpdir/repo/.env/nested"
  printf "seed\n" > "$tmpdir/repo/README.md"
  printf "plan\n" > "$tmpdir/repo/docs/PLANS.md"
  printf ".pw-browsers\n.env*\n" > "$tmpdir/repo/.gitignore"
  printf "PORT=5173\n" > "$tmpdir/repo/.env.cx.local"
  printf "INNER=1\n" > "$tmpdir/repo/.env/local"
  printf "NESTED=1\n" > "$tmpdir/repo/.env/nested/value"
  git -C "$tmpdir/repo" add README.md docs/PLANS.md .gitignore
  git -C "$tmpdir/repo" commit -m init >/dev/null

  output="$(cd "$tmpdir/repo" && CXHERE_RUNTIME=local cxhere env-copy 2>&1)"
  if ! printf "%s\n" "$output" | rg -F "worktree directory:" >/dev/null; then
    echo "expected local cxhere invocation to complete for env copy coverage" >&2
    exit 1
  fi

  worktree_dir="$tmpdir/repo-worktrees/env-copy"
  if [ ! -f "$worktree_dir/.env.cx.local" ]; then
    echo "expected cxhere to copy root env files into the worktree" >&2
    exit 1
  fi
  if [ ! -f "$worktree_dir/.env/local" ] || [ ! -f "$worktree_dir/.env/nested/value" ]; then
    echo "expected cxhere to recursively copy a root .env directory into the worktree" >&2
    exit 1
  fi
'; then
  echo "expected cxhere to copy root env files and directories into new worktrees" >&2
  exit 1
fi

echo "cxhere copies root env files and directories into new worktrees"
