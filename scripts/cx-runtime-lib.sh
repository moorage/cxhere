CXHERE_LABEL_REPO_KEY="com.moorage.sandbox-docker.repo"
CXHERE_LABEL_WORKTREE_KEY="com.moorage.sandbox-docker.worktree"
CXHERE_LABEL_IMAGE_KEY="com.moorage.sandbox-docker.image"
CXHERE_LABEL_RUNTIME_KEY="com.moorage.sandbox-docker.runtime"
CXHERE_LABEL_LAUNCH_CONFIG_KEY="com.moorage.sandbox-docker.launch-config"

cx_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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
      container delete --force "$@" >/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}
