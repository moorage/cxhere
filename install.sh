#!/usr/bin/env bash
set -euo pipefail

if [ -n "${BASH_SOURCE[0]:-}" ]; then
  CXHERE_INSTALLER_SOURCED=0
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    CXHERE_INSTALLER_SOURCED=1
  fi
else
  CXHERE_INSTALLER_SOURCED=0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
CXHERE_DEFAULT_REPO_SLUG="${CXHERE_REPO_SLUG:-moorage/cxhere}"
CXHERE_RELEASES_API="${CXHERE_RELEASES_API:-https://api.github.com/repos/${CXHERE_DEFAULT_REPO_SLUG}/releases/latest}"
CXHERE_RELEASES_PAGE="${CXHERE_RELEASES_PAGE:-https://github.com/${CXHERE_DEFAULT_REPO_SLUG}/releases}"
CXHERE_APPLE_CONTAINER_RELEASES_API="https://api.github.com/repos/apple/container/releases/latest"
CXHERE_APPLE_CONTAINER_RELEASES_PAGE="https://github.com/apple/container/releases"
CXHERE_HOME="${CXHERE_HOME:-$HOME/.cxhere}"

cx_host_macos_major_version() {
  sw_vers -productVersion 2>/dev/null | awk -F. '{print $1 + 0}'
}

cx_trim_version_prefix() {
  local raw
  raw="${1:-}"
  raw="${raw#container CLI version }"
  raw="${raw#v}"
  raw="${raw%% *}"
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

cx_version_lt() {
  [ "$(cx_version_sort_key "$1")" \< "$(cx_version_sort_key "$2")" ]
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

cx_now_epoch() {
  date +%s
}

cx_home_dir() {
  printf '%s\n' "$CXHERE_HOME"
}

cx_release_root_dir() {
  printf '%s\n' "$(cx_home_dir)/releases"
}

cx_stage_dir() {
  printf '%s\n' "$(cx_home_dir)/staging"
}

cx_state_dir() {
  printf '%s\n' "$(cx_home_dir)/state"
}

cx_current_link_path() {
  printf '%s\n' "$(cx_home_dir)/current"
}

cx_update_state_file() {
  printf '%s\n' "$(cx_state_dir)/latest-release"
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

cx_fetch_latest_release_metadata() {
  local release_json latest_version release_url tarball_url
  release_json="$(cx_curl_get "$CXHERE_RELEASES_API")" || return 1
  latest_version="$(cx_extract_release_tag_from_json "$release_json")"
  release_url="$(cx_extract_release_url_from_json "$release_json")"
  tarball_url="$(cx_extract_release_tarball_url_from_json "$release_json")"
  [ -n "$latest_version" ] || return 1
  [ -n "$release_url" ] || release_url="$CXHERE_RELEASES_PAGE"
  printf 'version=%s\nurl=%s\ntarball_url=%s\n' "$latest_version" "$release_url" "$tarball_url"
}

cx_container_runtime_ready() {
  command -v container >/dev/null 2>&1 || return 1
  container system status >/dev/null 2>&1
}

cx_docker_runtime_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker version --format '{{json .Server}}' >/dev/null 2>&1
}

cx_runtime_ready_silent() {
  case "${1:-}" in
    container) cx_container_runtime_ready ;;
    docker) cx_docker_runtime_ready ;;
    *) return 1 ;;
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
      printf '%s' "$inspect_json" | sed -n 's/.*"digest":"\([^"]*\)".*/\1/p' | head -n1
      ;;
  esac
}

cx_prompt_yes_no_installer() {
  local prompt reply default_answer
  prompt="$1"
  default_answer="${2:-N}"
  printf "%s" "$prompt" >&2
  IFS= read -r reply
  case "$reply" in
    "") [ "$default_answer" = "Y" ] && return 0 || return 1 ;;
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

cx_installer_detect_shell_rc_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    bash)
      if [ -f "$HOME/.bash_profile" ]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

cx_installer_source_line() {
  printf 'source "$HOME/.cxhere/current/scripts/codex-worktrees.zsh"\n'
}

cx_check_macos_and_container_release() {
  local latest_json latest_version latest_url installed_version

  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi

  if [ "$(cx_host_macos_major_version)" -lt 26 ]; then
    echo "macOS $(sw_vers -productVersion) detected; Apple container requires macOS 26 or newer." >&2
    return 0
  fi

  latest_json="$(cx_curl_get "$CXHERE_APPLE_CONTAINER_RELEASES_API" 2>/dev/null || true)"
  latest_version="$(cx_extract_release_tag_from_json "$latest_json")"
  latest_url="$(cx_extract_release_url_from_json "$latest_json")"
  [ -n "$latest_url" ] || latest_url="$CXHERE_APPLE_CONTAINER_RELEASES_PAGE"

  if command -v container >/dev/null 2>&1; then
    installed_version="$(container --version 2>/dev/null | sed -n 's/.*version //p' | head -n1)"
  else
    installed_version=""
  fi

  if [ -n "$latest_version" ] && [ -n "$installed_version" ] && ! cx_version_lt "$installed_version" "$latest_version"; then
    echo "Apple container is up to date at $installed_version" >&2
    return 0
  fi

  if [ -n "$installed_version" ]; then
    echo "Apple container update recommended: installed $installed_version, latest $latest_version" >&2
  else
    echo "Apple container is not installed. Latest release: ${latest_version:-unknown}" >&2
  fi

  if cx_prompt_yes_no_installer "Open the Apple container releases page? [y/N] " N; then
    if command -v open >/dev/null 2>&1; then
      open "$latest_url" >/dev/null 2>&1 || true
    else
      echo "Open this page to install/update Apple container: $latest_url" >&2
    fi
  else
    echo "Apple container releases: $latest_url" >&2
  fi
}

cx_install_latest_release() {
  local metadata version tarball_url release_url checked_at stage_root release_root current_link extract_root top_dir temp_root
  metadata="$(cx_fetch_latest_release_metadata)"
  version="$(printf '%s\n' "$metadata" | sed -n 's/^version=//p' | head -n1)"
  tarball_url="$(printf '%s\n' "$metadata" | sed -n 's/^tarball_url=//p' | head -n1)"
  release_url="$(printf '%s\n' "$metadata" | sed -n 's/^url=//p' | head -n1)"
  [ -n "$version" ] || {
    echo "failed to resolve latest cxhere release version" >&2
    return 1
  }
  [ -n "$tarball_url" ] || {
    echo "failed to resolve tarball URL for cxhere $version" >&2
    return 1
  }

  stage_root="$(cx_stage_dir)/$version"
  release_root="$(cx_release_root_dir)/$version"
  current_link="$(cx_current_link_path)"

  mkdir -p "$(cx_release_root_dir)" "$(cx_stage_dir)" "$(cx_state_dir)"

  if [ ! -d "$release_root" ]; then
    temp_root="${stage_root}.tmp.$$"
    rm -rf "$temp_root" "$stage_root"
    mkdir -p "$temp_root"
    extract_root="$temp_root/extract"
    mkdir -p "$extract_root"
    curl -fsSL "$tarball_url" | tar -xz -C "$extract_root"
    top_dir="$(find "$extract_root" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [ -n "$top_dir" ] || {
      echo "failed to unpack release $version" >&2
      rm -rf "$temp_root"
      return 1
    }
    mv "$top_dir" "$temp_root/release"
    printf '%s\n' "$version" > "$temp_root/release/VERSION"
    mv "$temp_root/release" "$stage_root"
    rm -rf "$release_root"
    mv "$stage_root" "$release_root"
    rm -rf "$temp_root"
  fi

  ln -sfn "$release_root" "$current_link"
  checked_at="$(cx_now_epoch)"
  cx_write_release_state "$(cx_update_state_file)" "$version" "$release_url" "$checked_at"
  printf '%s\n' "$version"
}

cx_ensure_shell_rc_source() {
  local rc_file source_line
  rc_file="$(cx_installer_detect_shell_rc_file)"
  source_line="$(cx_installer_source_line)"
  mkdir -p "$(dirname "$rc_file")"
  touch "$rc_file"
  if rg -F "$source_line" "$rc_file" >/dev/null 2>&1; then
    echo "shell rc already sources cxhere: $rc_file" >&2
    return 0
  fi
  if cx_prompt_yes_no_installer "Add cxhere to $rc_file? [Y/n] " Y; then
    printf '\n%s' "$source_line" >> "$rc_file"
    echo "updated $rc_file" >&2
  fi
}

cx_runtime_image_exists() {
  local runtime image_name
  runtime="$1"
  image_name="$2"
  [ -n "$(cx_local_image_identity "$runtime" "$image_name")" ]
}

cx_maybe_build_image() {
  local install_root image_name ready_runtimes existing_count build_runtime
  install_root="$(cx_current_link_path)"
  image_name="codex-cli:local"
  ready_runtimes=()
  existing_count=0
  if cx_runtime_ready_silent container; then
    ready_runtimes+=(container)
    if cx_runtime_image_exists container "$image_name"; then
      existing_count=$((existing_count + 1))
    fi
  fi
  if cx_runtime_ready_silent docker; then
    ready_runtimes+=(docker)
    if cx_runtime_image_exists docker "$image_name"; then
      existing_count=$((existing_count + 1))
    fi
  fi

  if [ "${#ready_runtimes[@]}" -eq 0 ]; then
    echo "no ready Apple container or Docker runtime found; skipping image build" >&2
    return 0
  fi

  if [ "$existing_count" -eq 0 ]; then
    if [ "${#ready_runtimes[@]}" -gt 1 ]; then
      build_runtime="all"
    else
      build_runtime="${ready_runtimes[0]}"
    fi
    echo "building $image_name for runtime: $build_runtime" >&2
    (cd "$install_root" && CX_BUILD_RUNTIME="$build_runtime" ./scripts/build-local.sh)
    return 0
  fi

  if cx_prompt_yes_no_installer "A local codex-cli:local image already exists. Rebuild it now? [y/N] " N; then
    if [ "${#ready_runtimes[@]}" -gt 1 ]; then
      build_runtime="all"
    else
      build_runtime="${ready_runtimes[0]}"
    fi
    (cd "$install_root" && CX_BUILD_RUNTIME="$build_runtime" ./scripts/build-local.sh)
  fi
}

main() {
  local installed_version current_script
  cx_check_macos_and_container_release
  installed_version="$(cx_install_latest_release)"
  echo "installed cxhere release $installed_version into $(cx_current_link_path)" >&2
  cx_ensure_shell_rc_source
  current_script="$(cx_current_link_path)/scripts/codex-worktrees.zsh"
  if [ "$CXHERE_INSTALLER_SOURCED" = "1" ]; then
    # shellcheck source=/dev/null
    . "$current_script"
    echo "re-sourced cxhere commands from $current_script" >&2
  else
    echo "run this to load cxhere into the current shell:" >&2
    echo "source \"$current_script\"" >&2
  fi
  cx_maybe_build_image
}

main "$@"
