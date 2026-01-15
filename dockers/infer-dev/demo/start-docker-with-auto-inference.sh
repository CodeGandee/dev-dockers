#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-infer-dev:stage-2}"
CONTAINER_NAME="${CONTAINER_NAME:-infer-dev-auto-infer}"

die() {
  echo "[demo] ERROR: $*" >&2
  exit 2
}

log() {
  echo "[demo] $*"
}

abs_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$1"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    die "Need either 'realpath' or 'python3' to resolve host paths"
  fi
  python3 - "$1" <<'PY'
import os
import sys

print(os.path.abspath(sys.argv[1]))
PY
}

usage() {
  cat <<'USAGE'
Usage: start-docker-with-auto-inference.sh [options]

Options:
  --port <host-port>                Map host port -> container 8080 (default: 11980)
  --llama-auto-serve on|off         Auto-start llama-server on boot (default: off)
  --llama-pkg <path-to-pkg>         llama.cpp bundle (.tar|.tar.gz|.tgz|.zip), installed on boot
  --llama-config <path-to-config>   TOML config file for check-and-run-llama-cpp.sh
  --model-dir <model-dir>           Model directory mounted to /llm-models/<basename>
  --dry-run                         Print the docker run command and exit
  -h, --help                        Show this help

Notes:
  - This script uses "docker run" (no docker compose).
  - llama.cpp package install is triggered by setting:
      AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1
      AUTO_INFER_LLAMA_CPP_PKG_PATH=<mounted pkg path>
  - Auto serving is controlled by:
      AUTO_INFER_LLAMA_CPP_ON_BOOT=1  (only when --llama-auto-serve on)
      AUTO_INFER_LLAMA_CPP_CONFIG=<mounted toml path>
USAGE
}

HOST_PORT=11980
LLAMA_AUTO_SERVE=off
LLAMA_PKG=""
LLAMA_CONFIG=""
MODEL_HOST_DIR=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      [[ $# -ge 2 ]] || die "--port requires a value"
      HOST_PORT="$2"; shift 2 ;;
    --llama-auto-serve)
      [[ $# -ge 2 ]] || die "--llama-auto-serve requires on|off"
      LLAMA_AUTO_SERVE="$2"; shift 2 ;;
    --llama-pkg)
      [[ $# -ge 2 ]] || die "--llama-pkg requires a path"
      LLAMA_PKG="$2"; shift 2 ;;
    --llama-config)
      [[ $# -ge 2 ]] || die "--llama-config requires a path"
      LLAMA_CONFIG="$2"; shift 2 ;;
    --model-dir)
      [[ $# -ge 2 ]] || die "--model-dir requires a path"
      MODEL_HOST_DIR="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1 (use --help)" ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  die "docker not found in PATH"
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  die "Docker image not found: $IMAGE (build it first)"
fi

if [[ ! "$HOST_PORT" =~ ^[0-9]+$ ]] || [[ "$HOST_PORT" -lt 1 ]] || [[ "$HOST_PORT" -gt 65535 ]]; then
  die "Invalid --port: $HOST_PORT"
fi

case "${LLAMA_AUTO_SERVE}" in
  on|off) ;;
  *) die "Invalid --llama-auto-serve: '$LLAMA_AUTO_SERVE' (use on|off)" ;;
esac

[[ -n "$LLAMA_PKG" ]] || die "--llama-pkg is required"
[[ -f "$LLAMA_PKG" ]] || die "llama pkg not found: $LLAMA_PKG"
LLAMA_PKG="$(abs_path "$LLAMA_PKG")"

case "$(basename -- "$LLAMA_PKG")" in
  *.tar|*.tar.gz|*.tgz|*.zip) ;;
  *) die "Unsupported --llama-pkg extension (supported: .tar, .tar.gz, .tgz, .zip)" ;;
esac

if [[ -n "$LLAMA_CONFIG" ]]; then
  [[ -f "$LLAMA_CONFIG" ]] || die "llama config not found: $LLAMA_CONFIG"
  LLAMA_CONFIG="$(abs_path "$LLAMA_CONFIG")"
fi

if [[ "$LLAMA_AUTO_SERVE" == "on" && -z "$LLAMA_CONFIG" ]]; then
  die "--llama-config is required when --llama-auto-serve on"
fi

if [[ -n "$MODEL_HOST_DIR" ]]; then
  [[ -d "$MODEL_HOST_DIR" ]] || die "model dir not found: $MODEL_HOST_DIR"
  MODEL_HOST_DIR="$(abs_path "$MODEL_HOST_DIR")"
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  log "Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

PKG_BASENAME="$(basename -- "$LLAMA_PKG")"
PKG_CONTAINER_PATH="/tmp/$PKG_BASENAME"

RUN_ENVS=(
  -e CUDA_HOME=/usr/local/cuda
  -e AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1
  -e "AUTO_INFER_LLAMA_CPP_PKG_PATH=$PKG_CONTAINER_PATH"
)

RUN_MOUNTS=(
  -v "$LLAMA_PKG:$PKG_CONTAINER_PATH:ro"
)

if [[ -n "$LLAMA_CONFIG" ]]; then
  CONFIG_BASENAME="$(basename -- "$LLAMA_CONFIG")"
  CONFIG_CONTAINER_PATH="/tmp/$CONFIG_BASENAME"
  RUN_ENVS+=( -e "AUTO_INFER_LLAMA_CPP_CONFIG=$CONFIG_CONTAINER_PATH" )
  RUN_MOUNTS+=( -v "$LLAMA_CONFIG:$CONFIG_CONTAINER_PATH:ro" )
fi

if [[ -n "$MODEL_HOST_DIR" ]]; then
  MODEL_BASENAME="$(basename -- "$MODEL_HOST_DIR")"
  MODEL_CONTAINER_DIR="/llm-models/$MODEL_BASENAME"
  RUN_MOUNTS+=( -v "$MODEL_HOST_DIR:$MODEL_CONTAINER_DIR:ro" )
fi

if [[ "$LLAMA_AUTO_SERVE" == "on" ]]; then
  RUN_ENVS+=( -e AUTO_INFER_LLAMA_CPP_ON_BOOT=1 )
fi

log "Starting container:"
log "  image: $IMAGE"
log "  name:  $CONTAINER_NAME"
log "  port:  ${HOST_PORT} -> 8080"
log "  llama auto serve: $LLAMA_AUTO_SERVE"

cmd=(docker run -d
  --name "$CONTAINER_NAME"
  --gpus all
  --add-host host.docker.internal:host-gateway
  -p "${HOST_PORT}:8080"
  "${RUN_ENVS[@]}"
  "${RUN_MOUNTS[@]}"
  "$IMAGE" sleep infinity
)

printf '[demo] '
printf '%q ' "${cmd[@]}"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

"${cmd[@]}" >/dev/null

log "Logs: docker logs -f $CONTAINER_NAME"
log "Stop: docker rm -f $CONTAINER_NAME"

# Wait until stage-2 custom entry has created helper links (and pkg install likely completed).
log "Waiting for container entry hooks..."
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER_NAME" bash -lc 'test -e /soft/app/llama-cpp/check-and-run-llama-cpp.sh' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! docker exec "$CONTAINER_NAME" bash -lc 'test -e /soft/app/llama-cpp/check-and-run-llama-cpp.sh' >/dev/null 2>&1; then
  echo >&2
  log "Entry hooks did not complete in time. Last logs:" >&2
  docker logs --tail 200 "$CONTAINER_NAME" >&2 || true
  exit 1
fi

if [[ "$LLAMA_AUTO_SERVE" == "on" ]]; then
  log "Waiting for /v1/models..."
  if command -v curl >/dev/null 2>&1; then
    for _ in $(seq 1 180); do
      if curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models" >/dev/null 2>&1; then
        log "Ready: http://127.0.0.1:${HOST_PORT}"
        exit 0
      fi
      sleep 2
    done

    echo >&2
    log "Server not ready yet. Last logs:" >&2
    docker logs --tail 200 "$CONTAINER_NAME" >&2 || true
    exit 1
  else
    log "curl not found; skipping readiness check."
  fi
else
  log "Manual serve:"
  log "  docker exec -it $CONTAINER_NAME /soft/app/llama-cpp/check-and-run-llama-cpp.sh"
fi
