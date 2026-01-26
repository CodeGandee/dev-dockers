#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$PROJECT_DIR/.." && pwd)
STAGE2_IMAGE_NAME='infer-dev:stage-2'
FORWARD=()
usage() {
  cat <<'USAGE'
Usage: build-merged.sh [OPTIONS] [--] [docker build flags]

Build the merged image using merged.Dockerfile and merged.env.

Options:
  -o, --output-image <name:tag>  Override output image tag (default from merged.env)
  -h, --help                     Show this help and exit

Pass-through:
  Use "--" to stop parsing and forward remaining flags directly to
  "docker build" (e.g. --no-cache, --progress=plain, --build-arg KEY=VAL).

Examples:
  ./build-merged.sh
  ./build-merged.sh -o myorg/myapp:dev
  ./build-merged.sh -- --no-cache --progress=plain
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    -o|--output-image)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output-image requires a value <name:tag>" >&2
        exit 1
      fi
      STAGE2_IMAGE_NAME="$2"; shift 2 ;;
    --)
      shift; FORWARD+=("$@"); break ;;
    *)
      # Pass any unknown args through to docker build
      FORWARD+=("$1"); shift ;;
  esac
done
set -a
source "$PROJECT_DIR/merged.env"
set +a

# Build docker build command incrementally to avoid empty-arg issues
cmd=( docker build   -f "$PROJECT_DIR/merged.Dockerfile"   -t "$STAGE2_IMAGE_NAME"   --add-host=host.docker.internal:host-gateway )

[[ -n "${BASE_IMAGE_1:-}" ]] && cmd+=( --build-arg BASE_IMAGE_1 )
[[ -n "${WITH_ESSENTIAL_APPS:-}" ]] && cmd+=( --build-arg WITH_ESSENTIAL_APPS )
cmd+=( --build-arg "WITH_SSH=${WITH_SSH:-}" )
cmd+=( --build-arg "SSH_USER_NAME=${SSH_USER_NAME:-}" )
cmd+=( --build-arg "SSH_USER_PASSWORD=${SSH_USER_PASSWORD:-}" )
cmd+=( --build-arg "SSH_USER_UID=${SSH_USER_UID:-}" )
cmd+=( --build-arg "SSH_USER_GID=${SSH_USER_GID:-}" )
cmd+=( --build-arg "SSH_PUBKEY_FILE=${SSH_PUBKEY_FILE:-}" )
cmd+=( --build-arg "SSH_PRIVKEY_FILE=${SSH_PRIVKEY_FILE:-}" )
cmd+=( --build-arg "SSH_CONTAINER_PORT=${SSH_CONTAINER_PORT:-}" )
[[ -n "${APT_SOURCE_FILE:-}" ]] && cmd+=( --build-arg APT_SOURCE_FILE )
[[ -n "${KEEP_APT_SOURCE_FILE:-}" ]] && cmd+=( --build-arg KEEP_APT_SOURCE_FILE )
[[ -n "${APT_USE_PROXY:-}" ]] && cmd+=( --build-arg APT_USE_PROXY )
[[ -n "${APT_KEEP_PROXY:-}" ]] && cmd+=( --build-arg APT_KEEP_PROXY )
[[ -n "${PEI_HTTP_PROXY_1:-}" ]] && cmd+=( --build-arg PEI_HTTP_PROXY_1 )
[[ -n "${PEI_HTTPS_PROXY_1:-}" ]] && cmd+=( --build-arg PEI_HTTPS_PROXY_1 )
[[ -n "${ENABLE_GLOBAL_PROXY:-}" ]] && cmd+=( --build-arg ENABLE_GLOBAL_PROXY )
[[ -n "${REMOVE_GLOBAL_PROXY_AFTER_BUILD:-}" ]] && cmd+=( --build-arg REMOVE_GLOBAL_PROXY_AFTER_BUILD )
[[ -n "${PEI_STAGE_HOST_DIR_1:-}" ]] && cmd+=( --build-arg PEI_STAGE_HOST_DIR_1 )
[[ -n "${PEI_STAGE_DIR_1:-}" ]] && cmd+=( --build-arg PEI_STAGE_DIR_1 )
[[ -n "${ROOT_PASSWORD:-}" ]] && cmd+=( --build-arg ROOT_PASSWORD )
[[ -n "${WITH_ESSENTIAL_APPS:-}" ]] && cmd+=( --build-arg WITH_ESSENTIAL_APPS )
[[ -n "${PEI_STAGE_HOST_DIR_2:-}" ]] && cmd+=( --build-arg PEI_STAGE_HOST_DIR_2 )
[[ -n "${PEI_STAGE_DIR_2:-}" ]] && cmd+=( --build-arg PEI_STAGE_DIR_2 )
[[ -n "${PEI_PREFIX_APPS:-}" ]] && cmd+=( --build-arg PEI_PREFIX_APPS )
[[ -n "${PEI_PREFIX_DATA:-}" ]] && cmd+=( --build-arg PEI_PREFIX_DATA )
[[ -n "${PEI_PREFIX_WORKSPACE:-}" ]] && cmd+=( --build-arg PEI_PREFIX_WORKSPACE )
[[ -n "${PEI_PREFIX_VOLUME:-}" ]] && cmd+=( --build-arg PEI_PREFIX_VOLUME )
[[ -n "${PEI_PREFIX_IMAGE:-}" ]] && cmd+=( --build-arg PEI_PREFIX_IMAGE )
[[ -n "${PEI_PATH_HARD:-}" ]] && cmd+=( --build-arg PEI_PATH_HARD )
[[ -n "${PEI_PATH_SOFT:-}" ]] && cmd+=( --build-arg PEI_PATH_SOFT )
[[ -n "${PEI_HTTP_PROXY_2:-}" ]] && cmd+=( --build-arg PEI_HTTP_PROXY_2 )
[[ -n "${PEI_HTTPS_PROXY_2:-}" ]] && cmd+=( --build-arg PEI_HTTPS_PROXY_2 )
[[ -n "${ENABLE_GLOBAL_PROXY:-}" ]] && cmd+=( --build-arg ENABLE_GLOBAL_PROXY )
[[ -n "${REMOVE_GLOBAL_PROXY_AFTER_BUILD:-}" ]] && cmd+=( --build-arg REMOVE_GLOBAL_PROXY_AFTER_BUILD )

# Forward any additional CLI arguments, if provided
if [[ ${#FORWARD[@]} -gt 0 ]]; then
  cmd+=( "${FORWARD[@]}" )
fi

# Build context
cmd+=( "$PROJECT_ROOT" )

printf '%q ' "${cmd[@]}"; echo
"${cmd[@]}"

echo "[merge] Done. Final image: $STAGE2_IMAGE_NAME"
