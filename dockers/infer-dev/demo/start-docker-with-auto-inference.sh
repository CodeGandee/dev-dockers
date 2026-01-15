#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
INFER_DIR="$REPO_ROOT/dockers/infer-dev"

IMAGE="${IMAGE:-infer-dev:stage-2}"
CONTAINER_NAME="${CONTAINER_NAME:-infer-dev-auto-infer}"
HOST_PORT="${HOST_PORT:-11980}"

CONFIG_HOST_DIR="$INFER_DIR/model-configs"
CONFIG_CONTAINER_DIR="${CONFIG_CONTAINER_DIR:-/model-configs}"
CONFIG_FILE="${CONFIG_FILE:-glm-4.7-q2k.toml}"

WORKSPACE_HOST_DIR="$INFER_DIR/.container/workspace"
WORKSPACE_CONTAINER_DIR="${WORKSPACE_CONTAINER_DIR:-/hard/volume/workspace}"

PKG_HOST_PATH="${PKG_HOST_PATH:-$WORKSPACE_HOST_DIR/llama-cpp-pkg.tgz}"
PKG_CONTAINER_PATH="${PKG_CONTAINER_PATH:-$WORKSPACE_CONTAINER_DIR/llama-cpp-pkg.tgz}"

MODEL_HOST_DIR="${MODEL_HOST_DIR:-/data1/huangzhe/llm-models/GLM-4.7-GGUF}"
MODEL_CONTAINER_DIR="${MODEL_CONTAINER_DIR:-/llm-models/GLM-4.7-GGUF}"

SSH_HOST_PORT="${SSH_HOST_PORT:-}" # optional, e.g. 2222

die() {
  echo "[demo] ERROR: $*" >&2
  exit 2
}

log() {
  echo "[demo] $*"
}

if ! command -v docker >/dev/null 2>&1; then
  die "docker not found in PATH"
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  die "Docker image not found: $IMAGE (build it first)"
fi

if [[ ! -f "$CONFIG_HOST_DIR/$CONFIG_FILE" ]]; then
  die "Config not found: $CONFIG_HOST_DIR/$CONFIG_FILE"
fi

if [[ ! -d "$MODEL_HOST_DIR" ]]; then
  die "Model dir not found: $MODEL_HOST_DIR (set MODEL_HOST_DIR=...)"
fi

mkdir -p "$WORKSPACE_HOST_DIR"

if [[ ! -f "$PKG_HOST_PATH" ]]; then
  LLAMA_CPP_BIN_DIR="$WORKSPACE_HOST_DIR/llama-cpp/build/bin"
  if [[ ! -x "$LLAMA_CPP_BIN_DIR/llama-server" ]]; then
    die "llama.cpp pkg not found ($PKG_HOST_PATH) and build not found ($LLAMA_CPP_BIN_DIR/llama-server)"
  fi

  log "Building llama.cpp pkg:"
  log "  src: $LLAMA_CPP_BIN_DIR"
  log "  dst: $PKG_HOST_PATH"

  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/payload/bin"
  cp -a "$LLAMA_CPP_BIN_DIR"/. "$TMP_DIR/payload/bin/"
  cat >"$TMP_DIR/payload/README.txt" <<'EOF'
llama.cpp binary bundle for infer-dev

Layout:
- bin/llama-server
- bin/*.so* (runtime shared libraries)
EOF
  tar -C "$TMP_DIR/payload" -czf "$PKG_HOST_PATH" .
  rm -rf "$TMP_DIR"
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  log "Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

PORT_ARGS=(-p "${HOST_PORT}:8080")
if [[ -n "$SSH_HOST_PORT" ]]; then
  PORT_ARGS+=(-p "${SSH_HOST_PORT}:22")
fi

log "Starting container:"
log "  image: $IMAGE"
log "  name:  $CONTAINER_NAME"
log "  port:  ${HOST_PORT} -> 8080"

docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  --add-host host.docker.internal:host-gateway \
  "${PORT_ARGS[@]}" \
  -e CUDA_HOME=/usr/local/cuda \
  -e AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1 \
  -e "AUTO_INFER_LLAMA_CPP_PKG_PATH=$PKG_CONTAINER_PATH" \
  -e AUTO_INFER_LLAMA_CPP_ON_BOOT=1 \
  -e "AUTO_INFER_LLAMA_CPP_CONFIG=$CONFIG_CONTAINER_DIR/$CONFIG_FILE" \
  -v "$WORKSPACE_HOST_DIR:$WORKSPACE_CONTAINER_DIR" \
  -v "$CONFIG_HOST_DIR:$CONFIG_CONTAINER_DIR:ro" \
  -v "$MODEL_HOST_DIR:$MODEL_CONTAINER_DIR:ro" \
  "$IMAGE" sleep infinity >/dev/null

log "Waiting for /v1/models..."
if command -v curl >/dev/null 2>&1; then
  for _ in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models" >/dev/null 2>&1; then
      log "Ready: http://127.0.0.1:${HOST_PORT}"
      log "Logs:  docker logs -f $CONTAINER_NAME"
      log "Stop:  docker rm -f $CONTAINER_NAME"
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
  log "Logs: docker logs -f $CONTAINER_NAME"
  exit 0
fi

