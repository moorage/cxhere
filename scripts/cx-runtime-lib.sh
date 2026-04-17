CXHERE_LABEL_REPO_KEY="com.moorage.cxhere.repo"
CXHERE_LABEL_WORKTREE_KEY="com.moorage.cxhere.worktree"
CXHERE_LABEL_IMAGE_KEY="com.moorage.cxhere.image"
CXHERE_LABEL_RUNTIME_KEY="com.moorage.cxhere.runtime"
CXHERE_LABEL_LAUNCH_CONFIG_KEY="com.moorage.cxhere.launch-config"
CXHERE_DEFAULT_REPO_SLUG="moorage/cxhere"
CXHERE_DEFAULT_RELEASES_API="https://api.github.com/repos/${CXHERE_DEFAULT_REPO_SLUG}/releases/latest"
CXHERE_DEFAULT_RELEASES_PAGE="https://github.com/${CXHERE_DEFAULT_REPO_SLUG}/releases"
CXHERE_DEFAULT_APPLE_CONTAINER_RELEASES_API="https://api.github.com/repos/apple/container/releases/latest"
CXHERE_DEFAULT_APPLE_CONTAINER_RELEASES_PAGE="https://github.com/apple/container/releases"
CXHERE_UPDATE_CACHE_TTL_SECONDS="${CXHERE_UPDATE_CACHE_TTL_SECONDS:-86400}"

cx_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

cx_read_first_line() {
  local file_path
  file_path="$1"
  [ -f "$file_path" ] || return 1
  IFS= read -r _cx_read_first_line_value < "$file_path" || true
  printf '%s\n' "${_cx_read_first_line_value:-}"
}

cx_trim_version_prefix() {
  local raw
  raw="${1:-}"
  raw="${raw#container CLI version }"
  raw="${raw#v}"
  printf '%s\n' "$raw"
}

cx_version_sort_key() {
  local raw major minor patch extra
  raw="$(cx_trim_version_prefix "${1:-}")"
  major=0
  minor=0
  patch=0
  extra=0
  IFS=. read -r major minor patch extra <<EOF
$raw
EOF
  major="${major%%[^0-9]*}"
  minor="${minor%%[^0-9]*}"
  patch="${patch%%[^0-9]*}"
  printf '%06d%06d%06d\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

cx_version_gt() {
  [ "$(cx_version_sort_key "$1")" -gt "$(cx_version_sort_key "$2")" ]
}

cx_version_lt() {
  [ "$(cx_version_sort_key "$1")" -lt "$(cx_version_sort_key "$2")" ]
}

cx_curl_get() {
  curl -fsSL --connect-timeout 5 --max-time 20 "$1"
}

cx_extract_release_tag_from_json() {
  printf '%s' "$1" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

cx_extract_release_url_from_json() {
  printf '%s' "$1" | sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

cx_extract_release_tarball_url_from_json() {
  printf '%s' "$1" | sed -n 's/.*"tarball_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

cx_repo_slug() {
  printf '%s\n' "${CXHERE_REPO_SLUG:-$CXHERE_DEFAULT_REPO_SLUG}"
}

cx_release_api_url() {
  printf '%s\n' "${CXHERE_RELEASES_API:-https://api.github.com/repos/$(cx_repo_slug)/releases/latest}"
}

cx_release_page_url() {
  printf '%s\n' "${CXHERE_RELEASES_PAGE:-https://github.com/$(cx_repo_slug)/releases}"
}

cx_home_dir() {
  printf '%s\n' "${CXHERE_HOME:-$HOME/.cxhere}"
}

cx_release_root_dir() {
  printf '%s\n' "$(cx_home_dir)/releases"
}

cx_current_link_path() {
  printf '%s\n' "$(cx_home_dir)/current"
}

cx_state_dir() {
  printf '%s\n' "$(cx_home_dir)/state"
}

cx_stage_dir() {
  printf '%s\n' "$(cx_home_dir)/staging"
}

cx_update_state_file() {
  printf '%s\n' "$(cx_state_dir)/latest-release"
}

cx_update_lock_dir() {
  printf '%s\n' "$(cx_state_dir)/update-check.lock"
}

cx_loaded_version() {
  printf '%s\n' "${CXHERE_VERSION:-dev}"
}

cx_current_installed_version() {
  local version_file current_link
  current_link="$(cx_current_link_path)"
  version_file="$current_link/VERSION"
  cx_read_first_line "$version_file" 2>/dev/null || true
}

cx_loaded_release_root() {
  if [ -n "${CXHERE_RELEASE_ROOT:-}" ]; then
    printf '%s\n' "$CXHERE_RELEASE_ROOT"
  elif [ -n "${CXHERE_SCRIPT_DIR:-}" ]; then
    cd "$CXHERE_SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P
  else
    return 1
  fi
}

cx_write_release_state() {
  local state_file version url checked_at
  state_file="$1"
  version="$2"
  url="$3"
  checked_at="$4"
  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
latest_version=$version
release_url=$url
checked_at=$checked_at
EOF
}

cx_read_release_state_value() {
  local state_file key
  state_file="$1"
  key="$2"
  [ -f "$state_file" ] || return 1
  sed -n "s/^${key}=//p" "$state_file" | head -n1
}

cx_update_state_latest_version() {
  cx_read_release_state_value "$(cx_update_state_file)" latest_version 2>/dev/null || true
}

cx_update_state_release_url() {
  cx_read_release_state_value "$(cx_update_state_file)" release_url 2>/dev/null || true
}

cx_update_state_checked_at() {
  cx_read_release_state_value "$(cx_update_state_file)" checked_at 2>/dev/null || true
}

cx_now_epoch() {
  date +%s
}

cx_update_state_is_fresh() {
  local checked_at now age
  checked_at="$(cx_update_state_checked_at)"
  [ -n "$checked_at" ] || return 1
  now="$(cx_now_epoch)"
  age=$((now - checked_at))
  [ "$age" -lt "$CXHERE_UPDATE_CACHE_TTL_SECONDS" ]
}

cx_fetch_latest_release_metadata() {
  local release_json latest_version release_url tarball_url
  release_json="$(cx_curl_get "$(cx_release_api_url)")" || return 1
  latest_version="$(cx_extract_release_tag_from_json "$release_json")"
  release_url="$(cx_extract_release_url_from_json "$release_json")"
  tarball_url="$(cx_extract_release_tarball_url_from_json "$release_json")"
  [ -n "$latest_version" ] || return 1
  [ -n "$release_url" ] || release_url="$(cx_release_page_url)"
  printf 'version=%s\nurl=%s\ntarball_url=%s\n' "$latest_version" "$release_url" "$tarball_url"
}

cx_background_update_check() {
  local lock_dir metadata latest_version release_url checked_at
  lock_dir="$(cx_update_lock_dir)"
  mkdir -p "$(cx_state_dir)"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    return 0
  fi
  trap 'rmdir "$lock_dir" >/dev/null 2>&1 || true' EXIT INT TERM
  metadata="$(cx_fetch_latest_release_metadata 2>/dev/null)" || return 0
  latest_version="$(printf '%s\n' "$metadata" | sed -n 's/^version=//p' | head -n1)"
  release_url="$(printf '%s\n' "$metadata" | sed -n 's/^url=//p' | head -n1)"
  checked_at="$(cx_now_epoch)"
  [ -n "$latest_version" ] || return 0
  cx_write_release_state "$(cx_update_state_file)" "$latest_version" "$release_url" "$checked_at"
}

cx_kickoff_background_update_check() {
  if cx_update_state_is_fresh; then
    return 0
  fi
  (
    cx_background_update_check
  ) >/dev/null 2>&1 &
}

cx_print_update_notice_if_needed() {
  local latest_version release_url loaded_version
  latest_version="$(cx_update_state_latest_version)"
  [ -n "$latest_version" ] || return 0
  loaded_version="$(cx_loaded_version)"
  if ! cx_version_gt "$latest_version" "$loaded_version"; then
    return 0
  fi
  release_url="$(cx_update_state_release_url)"
  echo "update available for cxhere: $loaded_version -> $latest_version" >&2
  echo "run: cxupdate" >&2
  if [ -n "$release_url" ]; then
    echo "release notes: $release_url" >&2
  fi
}

cx_warn_if_stale_shell_source() {
  local current_version loaded_version
  current_version="$(cx_current_installed_version)"
  loaded_version="$(cx_loaded_version)"
  [ -n "$current_version" ] || return 0
  [ "$current_version" = "$loaded_version" ] && return 0
  if [ "${CXHERE_STALE_SOURCE_WARNED:-0}" = "1" ]; then
    return 0
  fi
  CXHERE_STALE_SOURCE_WARNED=1
  export CXHERE_STALE_SOURCE_WARNED
  echo "cxhere commands are loaded from $loaded_version, but ~/.cxhere/current is $current_version" >&2
  echo "run: source \"$HOME/.cxhere/current/scripts/codex-worktrees.zsh\"" >&2
}

cx_command_prelude() {
  local command_name skip_update_check
  command_name="${1:-}"
  skip_update_check="${2:-0}"
  cx_warn_if_stale_shell_source
  cx_print_update_notice_if_needed
  if [ "$skip_update_check" != "1" ]; then
    cx_kickoff_background_update_check
  fi
  : "$command_name"
}

cx_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\//\\\//g'
}

cx_regex_escape() {
  printf '%s' "$1" | sed -e 's/[][(){}.^$+*?|\\/]/\\&/g'
}

cx_extract_first_digest() {
  local input
  input="${1:-}"
  printf '%s' "$input" \
    | rg -o -m1 '"digest":"sha256:[0-9a-f]+"' \
    | sed -E 's/.*"digest":"([^"]+)".*/\1/'
}

cx_sha256_value() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl dgst -sha256 -r | awk '{print $1}'
  else
    echo "no SHA-256 tool available (expected shasum, sha256sum, or openssl)" >&2
    return 1
  fi
}

cx_write_flat_global_gitconfig() {
  local source_file dest_file source_home line key value
  source_file="$1"
  dest_file="$2"
  source_home="${3:-$HOME}"

  [ -f "$source_file" ] || return 1
  mkdir -p "$(dirname "$dest_file")" || return 1
  : > "$dest_file" || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      include.path|includeIf.*.path)
        continue
        ;;
    esac
    git config --file "$dest_file" --add "$key" "$value" || return 1
  done <<EOF
$(HOME="$source_home" GIT_CONFIG_GLOBAL="$source_file" git config --global --includes --list)
EOF

  chmod 0644 "$dest_file" || true
}

cx_host_macos_major_version() {
  sw_vers -productVersion 2>/dev/null | awk -F. '{print $1 + 0}'
}

cx_container_host_supported() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 1
  [ "$(uname -m 2>/dev/null)" = "arm64" ] || return 1
  [ "$(cx_host_macos_major_version)" -ge 26 ] || return 1
  command -v container >/dev/null 2>&1
}

cx_container_runtime_ready() {
  cx_container_host_supported || return 1
  container system status >/dev/null 2>&1
}

cx_docker_runtime_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker version --format '{{json .Server}}' >/dev/null 2>&1
}

cx_requested_runtime() {
  if [ -n "${CXHERE_RUNTIME:-}" ]; then
    printf '%s\n' "$CXHERE_RUNTIME"
    return 0
  fi
  if cx_bool_is_true "${CXHERE_NO_DOCKER:-}"; then
    printf 'local\n'
    return 0
  fi
  printf 'auto\n'
}

cx_detect_runtime() {
  local requested
  requested="$(cx_requested_runtime)"
  case "$requested" in
    auto|"")
      if cx_container_runtime_ready; then
        printf 'container\n'
      elif cx_docker_runtime_ready; then
        printf 'docker\n'
      elif cx_container_host_supported; then
        printf 'container\n'
      elif command -v docker >/dev/null 2>&1; then
        printf 'docker\n'
      else
        printf 'docker\n'
      fi
      ;;
    container|docker|local)
      printf '%s\n' "$requested"
      ;;
    *)
      echo "invalid CXHERE_RUNTIME: $requested (expected auto, container, docker, or local)" >&2
      return 1
      ;;
  esac
}

cx_detect_build_runtime() {
  local requested
  requested="${CX_BUILD_RUNTIME:-auto}"
  case "$requested" in
    auto|"")
      if cx_container_runtime_ready; then
        printf 'container\n'
      elif cx_docker_runtime_ready; then
        printf 'docker\n'
      elif cx_container_host_supported; then
        printf 'container\n'
      elif command -v docker >/dev/null 2>&1; then
        printf 'docker\n'
      else
        printf 'docker\n'
      fi
      ;;
    container|docker|all)
      printf '%s\n' "$requested"
      ;;
    *)
      echo "invalid CX_BUILD_RUNTIME: $requested (expected auto, container, docker, or all)" >&2
      return 1
      ;;
  esac
}

cx_runtime_ready_silent() {
  case "${1:-}" in
    docker) cx_docker_runtime_ready ;;
    container) cx_container_runtime_ready ;;
    local) return 0 ;;
    *) return 1 ;;
  esac
}

cx_require_runtime() {
  local runtime
  runtime="$1"
  case "$runtime" in
    local)
      return 0
      ;;
    docker)
      if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed or not in PATH." >&2
        return 1
      fi
      if ! cx_docker_runtime_ready; then
        echo "Docker is installed but the daemon is unavailable. Start Docker Desktop or set CXHERE_RUNTIME=local." >&2
        return 1
      fi
      ;;
    container)
      if ! command -v container >/dev/null 2>&1; then
        echo "Apple container runtime is not installed or not in PATH." >&2
        return 1
      fi
      if ! cx_container_host_supported; then
        echo "Apple container runtime requires Apple silicon on macOS 26 or newer." >&2
        return 1
      fi
      if ! cx_container_runtime_ready; then
        echo "Apple container runtime is not ready. Run \`container system start\` or set CXHERE_RUNTIME=docker." >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported runtime: $runtime" >&2
      return 1
      ;;
  esac
}

cx_local_image_identity() {
  local runtime image_name inspect_json
  runtime="$1"
  image_name="$2"
  case "$runtime" in
    docker)
      docker image inspect -f '{{.Id}}' "$image_name" 2>/dev/null || true
      ;;
    container)
      inspect_json="$(container image inspect "$image_name" 2>/dev/null || true)"
      cx_extract_first_digest "$inspect_json"
      ;;
    *)
      return 1
      ;;
  esac
}

cx_container_image_identity() {
  local runtime container_id inspect_json
  runtime="$1"
  container_id="$2"
  case "$runtime" in
    docker)
      docker inspect -f '{{.Image}}' "$container_id" 2>/dev/null || true
      ;;
    container)
      inspect_json="$(container inspect "$container_id" 2>/dev/null || true)"
      cx_extract_first_digest "$inspect_json"
      ;;
    *)
      return 1
      ;;
  esac
}

cx_container_label_value() {
  local runtime container_id label_key inspect_json escaped_label_key
  runtime="$1"
  container_id="$2"
  label_key="$3"
  case "$runtime" in
    docker)
      docker inspect -f "{{with index .Config.Labels \"$label_key\"}}{{.}}{{end}}" "$container_id" 2>/dev/null || true
      ;;
    container)
      inspect_json="$(container inspect "$container_id" 2>/dev/null || true)"
      [ -n "$inspect_json" ] || return 0
      escaped_label_key="$(cx_regex_escape "$label_key")"
      printf '%s' "$inspect_json" \
        | rg -o -m1 "\"${escaped_label_key}\":\"[^\"]*\"" \
        | sed -E "s/.*\"${escaped_label_key}\":\"([^\"]*)\".*/\\1/"
      ;;
    *)
      return 1
      ;;
  esac
}

cx_require_local_image() {
  local runtime image_name local_image_id
  runtime="$1"
  image_name="$2"
  local_image_id="$(cx_local_image_identity "$runtime" "$image_name")"
  if [ -n "$local_image_id" ]; then
    return 0
  fi
  case "$runtime" in
    docker)
      echo "Local Docker image $image_name not found. Run \`CX_BUILD_RUNTIME=docker ./scripts/build-local.sh\`." >&2
      ;;
    container)
      echo "Local Apple container image $image_name not found. Run \`CX_BUILD_RUNTIME=container ./scripts/build-local.sh\`." >&2
      ;;
  esac
  return 1
}

cx_docker_find_labeled_worktree_containers() {
  local repo_root worktree_dir image_name
  repo_root="$1"
  worktree_dir="$2"
  image_name="$3"
  docker ps -q \
    --filter "label=${CXHERE_LABEL_REPO_KEY}=${repo_root}" \
    --filter "label=${CXHERE_LABEL_WORKTREE_KEY}=${worktree_dir}" \
    --filter "label=${CXHERE_LABEL_IMAGE_KEY}=${image_name}" 2>/dev/null || true
}

cx_docker_find_mount_worktree_containers() {
  local worktree_dir id
  worktree_dir="$1"
  docker ps -q 2>/dev/null | while read -r id; do
    [ -n "$id" ] || continue
    if docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$id" 2>/dev/null | rg -F -x "$worktree_dir" >/dev/null; then
      printf '%s\n' "$id"
    fi
  done
}

cx_container_has_label_match() {
  local inspect_json key escaped_value
  inspect_json="$1"
  key="$2"
  escaped_value="$(cx_json_escape "$3")"
  printf '%s' "$inspect_json" | rg -F "\"${key}\":\"${escaped_value}\"" >/dev/null
}

cx_container_launchd_label() {
  printf 'com.apple.container.container-runtime-linux.%s\n' "$1"
}

cx_container_launchd_service_ref() {
  printf 'gui/%s/%s\n' "$(id -u)" "$(cx_container_launchd_label "$1")"
}

cx_start_new_session() {
  [ "$#" -gt 0 ] || return 0

  # Run timeout-managed commands in their own session so a forced cleanup can
  # terminate any helper processes the CLI spawned before it wedged.
  exec perl -e '
    use strict;
    use warnings;
    use POSIX qw(setsid);
    setsid() or die "setsid failed: $!";
    exec @ARGV or die "exec failed: $!";
  ' -- "$@"
}

cx_kill_timeout_target() {
  local leader_pid
  leader_pid="$1"
  [ -n "$leader_pid" ] || return 0

  kill -TERM -- "-$leader_pid" 2>/dev/null || kill -TERM "$leader_pid" 2>/dev/null || true
  sleep 1
  kill -KILL -- "-$leader_pid" 2>/dev/null || kill -KILL "$leader_pid" 2>/dev/null || true
}

cx_run_with_timeout() {
  local timeout_seconds pid elapsed exit_code
  timeout_seconds="$1"
  shift
  [ "$#" -gt 0 ] || return 0

  cx_start_new_session "$@" &
  pid=$!
  elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      cx_kill_timeout_target "$pid"
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
  exit_code=$?
  return "$exit_code"
}

cx_container_runtime_job_stopped() {
  local container_id listed_ids
  container_id="$1"
  listed_ids="$(container list --quiet 2>/dev/null || true)"
  if printf '%s\n' "$listed_ids" | rg -F -x "$container_id" >/dev/null; then
    return 1
  fi
  return 0
}

cx_force_kill_container_runtime_job() {
  local container_id service_ref
  container_id="$1"
  service_ref="$(cx_container_launchd_service_ref "$container_id")"

  if ! launchctl kill SIGKILL "$service_ref" >/dev/null 2>&1; then
    return 1
  fi

  sleep 2
  cx_container_runtime_job_stopped "$container_id"
}

cx_delete_container_runtime_containers() {
  local cli_timeout stop_grace container_id forced_count
  cli_timeout="${CXHERE_CONTAINER_CLI_TIMEOUT:-15}"
  stop_grace="${CXHERE_CONTAINER_STOP_GRACE:-5}"
  [ "$#" -gt 0 ] || return 0

  if cx_run_with_timeout "$cli_timeout" container stop --time "$stop_grace" "$@" >/dev/null 2>&1; then
    return 0
  fi
  echo "warning: Apple container stop timed out or failed; trying kill" >&2

  if cx_run_with_timeout "$cli_timeout" container kill "$@" >/dev/null 2>&1; then
    return 0
  fi
  echo "warning: Apple container kill timed out or failed; trying delete --force" >&2

  if cx_run_with_timeout "$cli_timeout" container delete --force "$@" >/dev/null 2>&1; then
    return 0
  fi

  forced_count=0
  for container_id in "$@"; do
    if cx_force_kill_container_runtime_job "$container_id"; then
      forced_count=$((forced_count + 1))
    fi
  done
  if [ "$forced_count" -eq "$#" ]; then
    echo "warning: Apple container CLI stayed wedged; killed runtime job(s) via launchctl" >&2
    return 0
  fi

  echo "failed to terminate Apple container session(s); the container CLI did not finish within ${cli_timeout}s" >&2
  return 1
}

cx_list_worktree_containers() {
  local runtime repo_root worktree_dir image_name ids id inspect_json
  runtime="$1"
  repo_root="$2"
  worktree_dir="$3"
  image_name="$4"

  case "$runtime" in
    docker)
      ids="$(cx_docker_find_labeled_worktree_containers "$repo_root" "$worktree_dir" "$image_name")"
      if [ -n "$ids" ]; then
        printf '%s\n' "$ids"
        return 0
      fi
      cx_docker_find_mount_worktree_containers "$worktree_dir"
      ;;
    container)
      container list --quiet 2>/dev/null | while read -r id; do
        [ -n "$id" ] || continue
        inspect_json="$(container inspect "$id" 2>/dev/null || true)"
        [ -n "$inspect_json" ] || continue
        if cx_container_has_label_match "$inspect_json" "$CXHERE_LABEL_REPO_KEY" "$repo_root" \
          && cx_container_has_label_match "$inspect_json" "$CXHERE_LABEL_WORKTREE_KEY" "$worktree_dir" \
          && cx_container_has_label_match "$inspect_json" "$CXHERE_LABEL_IMAGE_KEY" "$image_name"; then
          printf '%s\n' "$id"
        fi
      done
      ;;
    *)
      return 1
      ;;
  esac
}

cx_delete_runtime_containers() {
  local runtime
  runtime="$1"
  shift
  [ "$#" -gt 0 ] || return 0
  case "$runtime" in
    docker)
      docker stop "$@" >/dev/null
      ;;
    container)
      cx_delete_container_runtime_containers "$@"
      ;;
    *)
      return 1
      ;;
  esac
}
