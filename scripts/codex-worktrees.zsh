#!/usr/bin/env zsh

cxhere() {
  # Run in a subshell so `set -e` can't terminate the caller's shell.
  # This avoids zsh exiting entirely when a command fails.
  ( set -e
  if [ -z "$1" ]; then
    echo "usage: cxhere <worktree-name> [session-id]" >&2
    echo "env: CXHERE_NO_DOCKER=1 to run codex locally without docker" >&2
    return 2
  fi

  local branch_name worktree_slug repo_root repo_parent repo_name worktrees_root worktree_dir
  local session_id
  local -a codex_args
  local plans_url plans_path create_plans
  local agents_url agents_path create_agents
  local env_file create_env_file
  local -a env_sources
  local gitignore_path create_gitignore add_env_ignore
  local repo_gitignore_path
  local playwright_browsers_path
  local playwright_browsers_rel
  local add_playwright_ignore
  local seccomp_profile_example
  local seccomp_profile_target
  local create_seccomp_profile
  local add_seccomp_ignore
  local -a env_file_arg
  local seccomp_profile
  local -a docker_security_opts
  local gh_config_dir use_gh gh_token
  local -a gh_config_arg
  local -a gh_token_arg
  local ssh_dir use_ssh
  local -a ssh_dir_arg
  local ssh_agent_sock use_ssh_agent
  local -a ssh_agent_arg
  local -a ssh_agent_env_arg
  local ssh_mount_target ssh_agent_mount_target
  local ngrok_config_dir use_ngrok
  local -a ngrok_config_arg
  local ngrok_mount_target
  local codex_config codex_config_dir add_workspace_trust
  local use_docker
  local pids_limit
  local tmpfs_tmp_size
  local tmpfs_home_size
  local shm_size
  local repo_root_mount repo_git_mount
  local -a docker_resource_opts
  repo_root="$(git rev-parse --show-toplevel)"
  branch_name="$1"
  session_id="$2"
  worktree_slug="${branch_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"
  plans_url="https://raw.githubusercontent.com/moorage/sandbox-docker/refs/heads/main/PLANS.example.project.md"
  plans_path="$worktree_dir/docs/PLANS.md"
  agents_url="https://raw.githubusercontent.com/moorage/sandbox-docker/refs/heads/main/AGENTS.example.global.md"
  agents_path="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
  codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  codex_config_dir="$(dirname "$codex_config")"
  env_file="$worktree_dir/.env.cx.local"
  gitignore_path="$worktree_dir/.gitignore"
  repo_gitignore_path="$repo_root/.gitignore"
  playwright_browsers_path="/workspace/.pw-browsers"
  playwright_browsers_rel=""
  seccomp_profile_example="$repo_root/seccomp_profile.example.json"
  seccomp_profile_target="$repo_root/seccomp_profile.json"
  env_file_arg=()
  seccomp_profile="$repo_root/seccomp_profile.json"
  docker_security_opts=(--security-opt=no-new-privileges)
  use_docker=1
  use_gh=1
  gh_config_dir="$HOME/.config/gh"
  gh_token=""
  gh_config_arg=()
  gh_token_arg=()
  use_ssh=1
  ssh_dir="$HOME/.ssh"
  ssh_dir_arg=()
  use_ssh_agent=1
  ssh_agent_sock="${SSH_AUTH_SOCK:-}"
  ssh_agent_arg=()
  ssh_agent_env_arg=()
  ssh_mount_target="/home/codex/.ssh"
  ssh_agent_mount_target="/tmp/ssh-agent.sock"
  use_ngrok=1
  ngrok_config_dir=""
  ngrok_config_arg=()
  ngrok_mount_target="/tmp/ngrok-home/.config/ngrok"
  docker_resource_opts=()
  repo_root_mount="$repo_root"
  repo_git_mount="$repo_root/.git"

  # Defaults tuned for running Playwright (headed Chromium) alongside a Node server.
  # These are all overrideable via env vars for tighter/looser setups.
  pids_limit="${CXHERE_PIDS_LIMIT:-2048}"
  tmpfs_tmp_size="${CXHERE_TMPFS_TMP_SIZE:-2g}"
  tmpfs_home_size="${CXHERE_TMPFS_HOME_SIZE:-2g}"
  shm_size="${CXHERE_SHM_SIZE:-1g}"
  docker_resource_opts+=(--pids-limit="$pids_limit")
  docker_resource_opts+=(--shm-size="$shm_size")
  docker_resource_opts+=(--ulimit "nproc=${CXHERE_ULIMIT_NPROC:-8192}:${CXHERE_ULIMIT_NPROC:-8192}")
  docker_resource_opts+=(--ulimit "nofile=${CXHERE_ULIMIT_NOFILE:-1048576}:${CXHERE_ULIMIT_NOFILE:-1048576}")

  case "${CXHERE_NO_DOCKER:-}" in
    1|true|TRUE|yes|YES|y|Y) use_docker=0 ;;
  esac
  case "${CXHERE_GH:-1}" in
    0|false|FALSE|no|NO|n|N) use_gh=0 ;;
  esac
  case "${CXHERE_SSH:-1}" in
    0|false|FALSE|no|NO|n|N) use_ssh=0 ;;
  esac
  case "${CXHERE_SSH_AGENT:-1}" in
    0|false|FALSE|no|NO|n|N) use_ssh_agent=0 ;;
  esac
  case "${CXHERE_NGROK:-1}" in
    0|false|FALSE|no|NO|n|N) use_ngrok=0 ;;
  esac

  if [ -n "${CXHERE_NGROK_CONFIG_DIR:-}" ]; then
    ngrok_config_dir="${CXHERE_NGROK_CONFIG_DIR%/}"
  elif [ -d "$HOME/.config/ngrok" ]; then
    ngrok_config_dir="$HOME/.config/ngrok"
  elif [ -d "$HOME/Library/Application Support/ngrok" ]; then
    ngrok_config_dir="$HOME/Library/Application Support/ngrok"
  elif [ -d "$HOME/.ngrok2" ]; then
    ngrok_config_dir="$HOME/.ngrok2"
  fi

  codex_workspace_trust_present() {
    [ -f "$codex_config" ] || return 1
    awk '
      BEGIN{in_section=0;ok=0}
      /^\[/{in_section=0}
      /^\[projects\."\/workspace"\]/{in_section=1}
      in_section && /^[[:space:]]*trust_level[[:space:]]*=[[:space:]]*"trusted"[[:space:]]*$/{ok=1}
      END{exit ok?0:1}
    ' "$codex_config"
  }

  codex_ensure_workspace_trust() {
    if codex_workspace_trust_present; then
      return 0
    fi

    echo "codex config missing trusted /workspace entry: $codex_config" >&2
    printf "%s" "Add it? [y/N] " >&2
    IFS= read -r add_workspace_trust
    if [[ "$add_workspace_trust" != [yY]* ]]; then
      return 0
    fi

    mkdir -p "$codex_config_dir"
    if [ ! -f "$codex_config" ]; then
      printf "%s\n" "[projects.\"/workspace\"]" "trust_level = \"trusted\"" > "$codex_config"
      echo "created $codex_config with /workspace trust" >&2
      return 0
    fi

    if rg -q '^\[projects\."\/workspace"\][[:space:]]*$' "$codex_config"; then
      local tmp_config
      tmp_config="$(mktemp)"
      awk '
        BEGIN{in_section=0;done=0}
        /^\[projects\."\/workspace"\]/{print; in_section=1; next}
        /^\[/{ if (in_section && !done){print "trust_level = \"trusted\""; done=1} in_section=0 }
        {
          if (in_section && $0 ~ /^[[:space:]]*trust_level[[:space:]]*=/) {
            if (!done) {print "trust_level = \"trusted\""; done=1}
            next
          }
          print
        }
        END{ if (in_section && !done) print "trust_level = \"trusted\"" }
      ' "$codex_config" > "$tmp_config"
      mv "$tmp_config" "$codex_config"
      echo "updated $codex_config with /workspace trust" >&2
    else
      printf "\n%s\n%s\n" "[projects.\"/workspace\"]" "trust_level = \"trusted\"" >> "$codex_config"
      echo "added /workspace trust to $codex_config" >&2
    fi
  }

  docker_find_worktree_containers() {
    local match_ids
    match_ids="$(
      docker ps -q | while read -r id; do
        if docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$id" | rg -F -x "$worktree_dir"; then
          echo "$id"
        fi
      done
    )"
    printf "%s\n" "$match_ids"
  }

  docker_local_image_id() {
    docker image inspect -f '{{.Id}}' codex-cli:local 2>/dev/null || true
  }

  docker_container_image_id() {
    local container_id="$1"
    docker inspect -f '{{.Image}}' "$container_id" 2>/dev/null || true
  }

  if [[ "$playwright_browsers_path" == /workspace/* ]]; then
    playwright_browsers_rel="${playwright_browsers_path#/workspace/}"
    if [ -n "$playwright_browsers_rel" ]; then
      if [ ! -f "$repo_gitignore_path" ]; then
        printf "%s\n" "$playwright_browsers_rel" > "$repo_gitignore_path"
        echo "created $repo_gitignore_path with $playwright_browsers_rel ignore"
      elif ! rg -q "^[[:space:]]*${playwright_browsers_rel//\//\\/}([[:space:]]*$|/)" "$repo_gitignore_path"; then
        printf "%s" "Add $playwright_browsers_rel to $repo_gitignore_path? [y/N] " >&2
        IFS= read -r add_playwright_ignore
        if [[ "$add_playwright_ignore" == [yY]* ]]; then
          printf "%s\n" "$playwright_browsers_rel" >> "$repo_gitignore_path"
          echo "added $playwright_browsers_rel to $repo_gitignore_path"
        fi
      fi
    fi
  fi

  if [ -f "$seccomp_profile_example" ] && [ ! -f "$seccomp_profile_target" ]; then
    printf "%s" "Copy seccomp profile to $seccomp_profile_target? [y/N] " >&2
    IFS= read -r create_seccomp_profile
    if [[ "$create_seccomp_profile" == [yY]* ]]; then
      cp "$seccomp_profile_example" "$seccomp_profile_target"
      echo "created $seccomp_profile_target"
    fi
  fi

  if [ ! -f "$repo_gitignore_path" ]; then
    printf "%s" "Create $repo_gitignore_path and ignore seccomp_profile.json? [y/N] " >&2
    IFS= read -r add_seccomp_ignore
    if [[ "$add_seccomp_ignore" == [yY]* ]]; then
      printf "%s\n" "seccomp_profile.json" > "$repo_gitignore_path"
      echo "created $repo_gitignore_path with seccomp_profile.json ignore"
    fi
  elif ! rg -q '^[[:space:]]*seccomp_profile\.json([[:space:]]*$|/)' "$repo_gitignore_path"; then
    printf "%s" "Add seccomp_profile.json to $repo_gitignore_path? [y/N] " >&2
    IFS= read -r add_seccomp_ignore
    if [[ "$add_seccomp_ignore" == [yY]* ]]; then
      printf "%s\n" "seccomp_profile.json" >> "$repo_gitignore_path"
      echo "added seccomp_profile.json to $repo_gitignore_path"
    fi
  fi

  mkdir -p "$worktrees_root"
  if git -C "$repo_root" worktree list --porcelain | rg -q "^worktree $worktree_dir$"; then
    if [ "$use_docker" -eq 1 ]; then
      local matching_ids
      matching_ids="$(docker_find_worktree_containers)"

      if [ -n "$matching_ids" ]; then
        local match_count
        local running_container_id
        local running_image_id
        local local_image_id
        match_count="$(printf "%s\n" "$matching_ids" | wc -l | tr -d ' ')"
        if [ "$match_count" -gt 1 ]; then
          echo "multiple containers running for worktree: $worktree_dir" >&2
          echo "example container: $(printf "%s\n" "$matching_ids" | head -n1)" >&2
          return 1
        fi
        running_container_id="$(printf "%s\n" "$matching_ids" | head -n1)"
        running_image_id="$(docker_container_image_id "$running_container_id")"
        local_image_id="$(docker_local_image_id)"

        if [ -n "$running_image_id" ] && [ -n "$local_image_id" ] && [ "$running_image_id" != "$local_image_id" ]; then
          echo "replacing stale container for worktree: $worktree_dir ($running_container_id)" >&2
          docker stop "$running_container_id" >/dev/null
        else
          echo "container already running for worktree: $worktree_dir ($running_container_id)" >&2
          return 0
        fi
      fi
    fi
  else
    if [ -e "$worktree_dir" ]; then
      echo "worktree directory exists but is not registered: $worktree_dir" >&2
      echo "hint: remove or rename it, or register it with: git worktree add \"$worktree_dir\" \"$branch_name\"" >&2
      return 1
    fi

    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
      git worktree add "$worktree_dir" "$branch_name"
    else
      git worktree add -b "$branch_name" "$worktree_dir"
    fi
  fi

  if [ ! -f "$plans_path" ]; then
    echo "missing plans file: $plans_path" >&2
    printf "%s" "Create it from $plans_url? [y/N] " >&2
    IFS= read -r create_plans
    if [[ "$create_plans" == [yY]* ]]; then
      mkdir -p "$(dirname "$plans_path")"
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$plans_url" -o "$plans_path"; then
          echo "failed to download plans template; please create $plans_path manually." >&2
        fi
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$plans_path" "$plans_url"; then
          echo "failed to download plans template; please create $plans_path manually." >&2
        fi
      else
        echo "neither curl nor wget is available; please create $plans_path manually." >&2
      fi
    fi
  fi

  if [ ! -f "$agents_path" ]; then
    echo "missing agents file: $agents_path" >&2
    printf "%s" "Create it from $agents_url? [y/N] " >&2
    IFS= read -r create_agents
    if [[ "$create_agents" == [yY]* ]]; then
      mkdir -p "$(dirname "$agents_path")"
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$agents_url" -o "$agents_path"; then
          echo "failed to download agents template; please create $agents_path manually." >&2
        fi
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$agents_path" "$agents_url"; then
          echo "failed to download agents template; please create $agents_path manually." >&2
        fi
      else
        echo "neither curl nor wget is available; please create $agents_path manually." >&2
      fi
    fi
  fi

  if [ -n "${ZSH_VERSION-}" ]; then
    setopt local_options null_glob
  elif [ -n "${BASH_VERSION-}" ]; then
    local _nullglob_restore
    _nullglob_restore="$(shopt -p nullglob)"
    shopt -s nullglob
  fi
  env_sources=("$repo_root"/.env*)
  if (( ${#env_sources[@]} )); then
    local env_source env_target
    for env_source in "${env_sources[@]}"; do
      if [ -f "$env_source" ]; then
        env_target="$worktree_dir/$(basename "$env_source")"
        if [ ! -f "$env_target" ]; then
          cp "$env_source" "$env_target"
          echo "copied env file: $env_target"
        fi
      fi
    done
  fi

  if [ ! -f "$env_file" ]; then
    echo "missing env file: $env_file" >&2
    printf "%s" "Create it? [y/N] " >&2
    IFS= read -r create_env_file
    if [[ "$create_env_file" == [yY]* ]]; then
      : > "$env_file"
      echo "created env file: $env_file"
    fi
  fi

  if [ ! -f "$gitignore_path" ]; then
    printf "%s" "Create $gitignore_path and ignore .env* files? [y/N] " >&2
    IFS= read -r create_gitignore
    if [[ "$create_gitignore" == [yY]* ]]; then
      printf "%s\n" ".env*" > "$gitignore_path"
      echo "created $gitignore_path with .env* ignore"
    fi
  elif ! rg -q '^[[:space:]]*\.env([[:space:]]*$|\*|[.])' "$gitignore_path"; then
    printf "%s" "Add .env* to $gitignore_path? [y/N] " >&2
    IFS= read -r add_env_ignore
    if [[ "$add_env_ignore" == [yY]* ]]; then
      printf "%s\n" ".env*" >> "$gitignore_path"
      echo "added .env* to $gitignore_path"
    fi
  fi

  if [ -n "${BASH_VERSION-}" ] && [ -n "${_nullglob_restore-}" ]; then
    eval "$_nullglob_restore"
  fi

  codex_ensure_workspace_trust

  echo "worktree directory: $worktree_dir"
  if command -v code >/dev/null 2>&1; then
    echo "open in VS Code: code \"$worktree_dir\""
  fi
  if command -v cursor >/dev/null 2>&1; then
    echo "open in Cursor: cursor \"$worktree_dir\""
  fi
  if command -v codium >/dev/null 2>&1; then
    echo "open in VSCodium: codium \"$worktree_dir\""
  fi
  if command -v open >/dev/null 2>&1; then
    echo "open in Finder: open \"$worktree_dir\""
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    echo "open in file manager: xdg-open \"$worktree_dir\""
  fi
  if command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then
    echo "open in Explorer (WSL): explorer.exe \"$(wslpath -w "$worktree_dir")\""
  elif command -v explorer.exe >/dev/null 2>&1; then
    echo "open in Explorer: explorer.exe \"$(pwd -W 2>/dev/null)\""
  fi

  if [ -f "$env_file" ]; then
    env_file_arg=(--env-file "$env_file")
  fi

  codex_args=()
  if [ -n "$session_id" ]; then
    codex_args=(resume "$session_id")
  fi

  if [ "$use_docker" -eq 1 ]; then
    if [ -f "$seccomp_profile" ]; then
	    docker_security_opts+=(--security-opt "seccomp=$seccomp_profile")
	    fi
	    if [ "$use_gh" -eq 1 ]; then
      if [ -d "$gh_config_dir" ]; then
        gh_config_arg=(-v "$gh_config_dir":/home/codex/.config/gh:rw)
      else
        echo "warning: gh config not found at $gh_config_dir; skipping gh mount" >&2
      fi

      if [ -n "${GH_TOKEN:-}" ]; then
        gh_token="$GH_TOKEN"
      elif [ -n "${GITHUB_TOKEN:-}" ]; then
        gh_token="$GITHUB_TOKEN"
      elif command -v gh >/dev/null 2>&1; then
        gh_token="$(gh auth token 2>/dev/null || true)"
      fi

      if [ -n "$gh_token" ]; then
        gh_token_arg=(-e GH_TOKEN="$gh_token")
      else
        echo "warning: no GitHub token available from GH_TOKEN, GITHUB_TOKEN, or gh auth token; container gh auth may be unavailable" >&2
      fi
		    fi
    if [ "$use_ssh" -eq 1 ]; then
      if [ -d "$ssh_dir" ]; then
        ssh_dir_arg=(-v "$ssh_dir":"$ssh_mount_target":ro)
      else
        echo "warning: ssh config not found at $ssh_dir; skipping ssh mount" >&2
      fi
    fi
    if [ "$use_ssh_agent" -eq 1 ] && [ -n "$ssh_agent_sock" ]; then
      if [ -S "$ssh_agent_sock" ]; then
        ssh_agent_arg=(-v "$ssh_agent_sock":"$ssh_agent_mount_target")
        ssh_agent_env_arg=(-e SSH_AUTH_SOCK="$ssh_agent_mount_target")
      else
        echo "warning: SSH_AUTH_SOCK is not a socket at $ssh_agent_sock; skipping ssh-agent mount" >&2
      fi
    fi
    if [ "$use_ngrok" -eq 1 ]; then
      if [ -n "$ngrok_config_dir" ] && [ -f "$ngrok_config_dir/ngrok.yml" ]; then
        ngrok_config_arg=(-v "$ngrok_config_dir":"$ngrok_mount_target":rw)
      elif [ -n "$ngrok_config_dir" ]; then
        echo "warning: ngrok config not found at $ngrok_config_dir/ngrok.yml; skipping ngrok mount" >&2
      fi
    fi
	    docker run --rm -it \
	      --init \
	      --ipc=host \
	      --user codex \
	      --cap-drop=ALL \
	      "${docker_security_opts[@]}" \
	      "${docker_resource_opts[@]}" \
	      --read-only \
	      --tmpfs "/tmp:rw,noexec,nosuid,nodev,size=${tmpfs_tmp_size}" \
	      --tmpfs "/home/codex:rw,noexec,nosuid,nodev,size=${tmpfs_home_size},uid=10001,gid=10001" \
	      -v "$worktree_dir":/workspace:rw \
	      -v "$repo_root_mount":"$repo_root_mount":ro \
	      -v "$repo_git_mount":"$repo_git_mount":rw \
		      -v "$HOME/.gitconfig":/home/codex/.gitconfig:ro \
		      -v "$HOME/.codex":/home/codex/.codex:rw \
		      "${gh_config_arg[@]}" \
		      "${gh_token_arg[@]}" \
		      "${ssh_dir_arg[@]}" \
		      "${ssh_agent_arg[@]}" \
	      "${ngrok_config_arg[@]}" \
	      "${env_file_arg[@]}" \
	      -e CODEX_HOME=/home/codex/.codex \
	      -e GH_CONFIG_DIR=/home/codex/.config/gh \
	      -e NPM_CONFIG_CACHE=/home/codex/.npm \
	      -e TMPDIR=/tmp \
	      -e HOME=/tmp/pulse-home \
	      -e XDG_RUNTIME_DIR=/tmp/xdg-runtime \
	      -e XDG_CONFIG_HOME=/tmp/pulse-home/.config \
	      -e XDG_CACHE_HOME=/tmp/pulse-home/.cache \
	      -e DISPLAY="${DISPLAY:-:99}" \
	      -e XVFB_SCREEN="${XVFB_SCREEN:-1920x1080x24}" \
	      -e PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/xdg-runtime/pulse/native}" \
	      -e PULSE_COOKIE=/tmp/xdg-runtime/pulse/cookie \
	      -e PULSE_CLIENTCONFIG=/tmp/xdg-runtime/pulse/client.conf \
	      "${ssh_agent_env_arg[@]}" \
	      -e HARNESS_CAPTURE_WITH_FFMPEG="${HARNESS_CAPTURE_WITH_FFMPEG:-1}" \
	      -e HARNESS_CAPTURE_AUDIO_FORMAT="${HARNESS_CAPTURE_AUDIO_FORMAT:-pulse}" \
	      -w /workspace \
	      codex-cli:local \
	      "${codex_args[@]}" \
	      --dangerously-bypass-approvals-and-sandbox \
	      --search
  else
    if [ -f "$env_file" ]; then
      set -a
      . "$env_file"
      set +a
    fi
    if ! command -v codex >/dev/null 2>&1; then
      echo "codex CLI not found in PATH; install it or enable Docker mode." >&2
      return 1
    fi
    (cd "$worktree_dir" && codex "${codex_args[@]}" --dangerously-bypass-approvals-and-sandbox --search)
  fi
  )
}

cxclose() {
  # Run in a subshell so command failures can't terminate the caller's shell.
  ( set -e
  local repo_root repo_parent repo_name worktrees_root requested_name worktree_dir worktree_slug git_dir git_common_dir
  local status_output locked_line tracked_path tracked_branch resolved_worktree resolved_branch
  local candidate_count

  if [ -z "$1" ]; then
    echo "usage: cxclose <worktree-name>" >&2
    return 2
  fi

  if ! git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    echo "not inside a git repository; run cxclose from the main repo or a worktree." >&2
    return 1
  fi
  repo_root="$(dirname "$git_common_dir")"
  requested_name="$1"
  worktree_slug="${requested_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"

  candidate_count="$(
    git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" -v req="$requested_name" -v expected="$worktree_dir" '
      $1=="worktree"{wt=$2; branch=""; inwt=1; next}
      $1=="branch" && inwt{branch=$2; next}
      $0==""{
        if (index(wt, base)==1) {
          b=branch
          sub(/^refs\/heads\//, "", b)
          n=wt
          sub(/^.*\//, "", n)
          if (wt==expected || wt==req || n==req || b==req) count++
        }
        inwt=0
      }
      END{print count+0}
    '
  )"

  if [ "$candidate_count" -gt 1 ]; then
    echo "multiple matching worktrees for '$requested_name'; be more specific." >&2
    git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" -v req="$requested_name" -v expected="$worktree_dir" '
      $1=="worktree"{wt=$2; branch=""; inwt=1; next}
      $1=="branch" && inwt{branch=$2; next}
      $0==""{
        if (index(wt, base)==1) {
          b=branch
          sub(/^refs\/heads\//, "", b)
          n=wt
          sub(/^.*\//, "", n)
          if (wt==expected || wt==req || n==req || b==req) {
            printf "- %s | %s\n", wt, (b=="" ? "<detached>" : b)
          }
        }
        inwt=0
      }
    '
    return 1
  fi

  tracked_path="$(
    git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" -v req="$requested_name" -v expected="$worktree_dir" '
      $1=="worktree"{wt=$2; branch=""; inwt=1; next}
      $1=="branch" && inwt{branch=$2; next}
      $0==""{
        if (index(wt, base)==1) {
          b=branch
          sub(/^refs\/heads\//, "", b)
          n=wt
          sub(/^.*\//, "", n)
          if (wt==expected || wt==req || n==req || b==req) {
            print wt
            exit
          }
        }
        inwt=0
      }
    '
  )"
  tracked_branch="$(
    git -C "$repo_root" worktree list --porcelain | awk -v wt="$tracked_path" '
      $1=="worktree"{inwt=($2==wt); next}
      inwt && $1=="branch"{print $2; exit}
      $0==""{inwt=0}
    '
  )"

  if [ -z "$tracked_path" ]; then
    echo "worktree not found for: $requested_name" >&2
    echo "hint: provide a codex worktree path, directory name, or branch name." >&2
    return 1
  fi
  resolved_worktree="$tracked_path"
  resolved_branch="${tracked_branch#refs/heads/}"

  locked_line="$(git -C "$repo_root" worktree list --porcelain | awk -v wt="$resolved_worktree" '
    $1=="worktree"{inwt=($2==wt)}
    inwt && $1=="locked"{print $0}
  ')"

  if [ -n "$locked_line" ]; then
    echo "worktree is locked (busy): $locked_line" >&2
    echo "hint: unlock it with: git worktree unlock \"$resolved_worktree\"" >&2
    return 1
  fi

  if git -C "$resolved_worktree" rev-parse --git-dir >/dev/null 2>&1; then
    git_dir="$(git -C "$resolved_worktree" rev-parse --git-dir)"
    if [ -f "$git_dir/index.lock" ] || [ -f "$git_dir/HEAD.lock" ]; then
      echo "worktree appears busy (git lock files present)." >&2
      echo "hint: ensure no git process or container is using it, then retry." >&2
      return 1
    fi
  fi

  status_output="$(git -C "$resolved_worktree" status --porcelain)"
  if [ -n "$status_output" ]; then
    echo "worktree has uncommitted changes; refusing to remove." >&2
    echo "hint: commit/stash changes or clean the worktree, then retry." >&2
    return 1
  fi

  git -C "$repo_root" worktree remove "$resolved_worktree"
  if [ -n "$tracked_branch" ] && [ -n "$resolved_branch" ]; then
    git -C "$repo_root" branch -d "$resolved_branch"
  fi
  )
}

cxkill() {
  # Run in a subshell so command failures can't terminate the caller's shell.
  ( set -e
  local repo_root repo_parent repo_name worktrees_root branch_name worktree_dir worktree_slug
  local matching_ids match_count

  if [ -z "$1" ]; then
    echo "usage: cxkill <worktree-name>" >&2
    return 2
  fi

  repo_root="$(git rev-parse --show-toplevel)"
  branch_name="$1"
  worktree_slug="${branch_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"

  matching_ids="$(
    docker ps -q | while read -r id; do
      if docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$id" | rg -F -x "$worktree_dir"; then
        echo "$id"
      fi
    done
  )"

  if [ -z "$matching_ids" ]; then
    echo "no running containers found for worktree: $worktree_dir" >&2
    return 0
  fi

  match_count="$(printf "%s\n" "$matching_ids" | wc -l | tr -d ' ')"
  echo "stopping $match_count container(s) for worktree: $worktree_dir" >&2
  docker stop $(printf "%s\n" "$matching_ids")
  )
}

cxlist() {
  set -e
  local repo_root repo_parent repo_name worktrees_root list_output

  repo_root="$(git rev-parse --show-toplevel)"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"

  echo "codex worktrees under $worktrees_root:"
  list_output="$(git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" '
    $1=="worktree"{
      wt=$2; branch=""; head=""; locked=""; prunable=""
      next
    }
    $1=="branch"{branch=$2}
    $1=="HEAD"{head=$2}
    $1=="locked"{locked="locked"}
    $1=="prunable"{prunable="prunable"}
    $0==""{
      if (index(wt, base)==1) {
        status=""
        if (locked!="") status=status locked " "
        if (prunable!="") status=status prunable " "
        if (status=="") status="ok"
        printf "- %s | %s | %s\n", wt, branch, status
      }
    }
  ')"
  if [ -z "$list_output" ]; then
    echo "no active codex worktrees."
    return 0
  fi
  printf "%s\n" "$list_output"
}

cx_worktree_names() {
  local repo_root repo_parent repo_name worktrees_root

  if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    return 0
  fi
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"

  git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" '
    $1=="worktree"{wt=$2; branch=""; inwt=1; next}
    $1=="branch" && inwt{branch=$2; next}
    $0==""{
      if (index(wt, base)==1 && branch ~ /^refs\/heads\//) {
        sub(/^refs\/heads\//, "", branch)
        print branch
      }
      inwt=0
    }
  '
}

if [ -n "${ZSH_VERSION-}" ]; then
  _cxclose_complete() {
    local -a worktrees
    worktrees=("${(@f)$(cx_worktree_names)}")
    if (( ${#worktrees[@]} > 0 )); then
      compadd -- "${worktrees[@]}"
    fi
  }

  _cxhere() {
    _arguments '1:worktree name:_cxclose_complete' '2:session id: '
  }

  _cxclose() {
    _arguments '1:worktree name:_cxclose_complete'
  }

  _cxkill() {
    _arguments '1:worktree name:_cxclose_complete'
  }

  if typeset -f compdef >/dev/null 2>&1; then
    compdef _cxhere cxhere
    compdef _cxclose cxclose
    compdef _cxkill cxkill
  fi
fi

if [ -n "${BASH_VERSION-}" ]; then
  _cxworktree_bash_complete() {
    local cur options
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -ne 1 ]; then
      COMPREPLY=()
      return 0
    fi
    options="$(cx_worktree_names | tr '\n' ' ')"
    COMPREPLY=($(compgen -W "$options" -- "$cur"))
  }
  complete -F _cxworktree_bash_complete cxhere 2>/dev/null || true
  complete -F _cxworktree_bash_complete cxclose 2>/dev/null || true
  complete -F _cxworktree_bash_complete cxkill 2>/dev/null || true
fi
