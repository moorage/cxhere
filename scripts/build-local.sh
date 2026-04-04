#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
IMAGE_NAME="codex-cli:local"
CACHE_FILE="$ROOT_DIR/.build-cachebust"

# shellcheck source=./cx-runtime-lib.sh
. "$SCRIPT_DIR/cx-runtime-lib.sh"

cx_delete_image_tag_docker() {
  local tag
  tag="$1"
  if docker image inspect "$tag" >/dev/null 2>&1; then
    docker image rm -f "$tag" >/dev/null
  fi
}

cx_delete_image_tag_container() {
  local tag
  tag="$1"
  if container image inspect "$tag" >/dev/null 2>&1; then
    container image delete --force "$tag" >/dev/null
  fi
}

cx_build_image_docker() {
  local npm_cachebust
  npm_cachebust="$1"
  cx_require_runtime docker
  for tag in "$IMAGE_NAME" "$PROJECT_NAME"; do
    cx_delete_image_tag_docker "$tag"
  done
  docker build \
    --build-arg NPM_CACHEBUST="$npm_cachebust" \
    -t "$IMAGE_NAME" \
    "$ROOT_DIR"
}

cx_build_image_container() {
  local npm_cachebust
  local -a build_args
  npm_cachebust="$1"
  cx_require_runtime container
  for tag in "$IMAGE_NAME" "$PROJECT_NAME"; do
    cx_delete_image_tag_container "$tag"
  done
  build_args=(
    build
    --build-arg "NPM_CACHEBUST=$npm_cachebust"
    -t "$IMAGE_NAME"
  )
  if [ -n "${CX_BUILD_CPUS:-}" ]; then
    build_args+=(--cpus "$CX_BUILD_CPUS")
  fi
  if [ -n "${CX_BUILD_MEMORY:-}" ]; then
    build_args+=(--memory "$CX_BUILD_MEMORY")
  fi
  if [ -n "${CX_BUILD_PLATFORM:-}" ]; then
    build_args+=(--platform "$CX_BUILD_PLATFORM")
  fi
  build_args+=("$ROOT_DIR")
  container "${build_args[@]}"
}

npm_cachebust=1
if [ -f "$CACHE_FILE" ]; then
  IFS=' ' read -r npm_cachebust < "$CACHE_FILE" || true
fi
npm_cachebust=$((npm_cachebust + 1))
printf "%s\n" "$npm_cachebust" > "$CACHE_FILE"

cd "$ROOT_DIR"

case "$(cx_detect_build_runtime)" in
  docker)
    cx_build_image_docker "$npm_cachebust"
    ;;
  container)
    cx_build_image_container "$npm_cachebust"
    ;;
  all)
    cx_build_image_docker "$npm_cachebust"
    cx_build_image_container "$npm_cachebust"
    ;;
esac
