#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[litellm] $*"
}

warn() {
  echo "[litellm] Warning: $*" >&2
}

normalize_bool() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo ""
    return 0
  fi
  case "${val,,}" in
    1|true) echo 1 ;;
    0|false) echo 0 ;;
    *) echo "$val" ;;
  esac
}

port_open() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
}

run_as_user() {
  local user="$1"
  shift

  if [[ -z "$user" || "$user" == "$(whoami)" ]]; then
    "$@"
    return 0
  fi

  if [[ "$(whoami)" != "root" ]]; then
    warn "Cannot switch to user '$user' (not root). Running as $(whoami)."
    "$@"
    return 0
  fi

  if ! id -u "$user" >/dev/null 2>&1; then
    warn "User '$user' does not exist. Running as root."
    "$@"
    return 0
  fi

  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    su -l "$user" -c "$(printf '%q ' "$@")"
  fi
}

ON_BOOT="$(normalize_bool "${AUTO_INFER_LITELLM_ON_BOOT:-0}")"
case "${ON_BOOT}" in
  1) ;;
  0|"") exit 0 ;;
  *) warn "AUTO_INFER_LITELLM_ON_BOOT='${AUTO_INFER_LITELLM_ON_BOOT:-}' not understood; treating as false."; exit 0 ;;
esac

LITELLM_USER="${AUTO_INFER_LITELLM_USER:-me}"
LITELLM_HOST="${AUTO_INFER_LITELLM_HOST:-0.0.0.0}"
LITELLM_PORT="${AUTO_INFER_LITELLM_PORT:-8010}"
PROXY_PORT="${AUTO_INFER_LITELLM_PROXY_PORT:-11899}"

LITELLM_LOG_FILE="${AUTO_INFER_LITELLM_LOG_FILE:-/tmp/litellm.log}"
PROXY_LOG_FILE="${AUTO_INFER_LITELLM_PROXY_LOG_FILE:-/tmp/litellm-proxy.log}"

CONFIG_FILE="${AUTO_INFER_LITELLM_CONFIG:-/soft/app/litellm/config.yaml}"

BACKEND_BASE="${AUTO_INFER_LITELLM_BACKEND_BASE:-http://127.0.0.1:8080/v1}"
BACKEND_MODEL="${AUTO_INFER_LITELLM_BACKEND_MODEL:-glm4}"
MASTER_KEY="${AUTO_INFER_LITELLM_MASTER_KEY:-sk-litellm-master}"

PROXY_SCRIPT="${AUTO_INFER_LITELLM_PROXY_SCRIPT:-/pei-from-host/stage-2/system/litellm/proxy.py}"
PROXY_PYTHON="${AUTO_INFER_LITELLM_PROXY_PYTHON:-python3}"
if [[ ! -x "$PROXY_PYTHON" ]]; then
  PROXY_PYTHON="python3"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Config not found; generating default config at: $CONFIG_FILE"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat >"$CONFIG_FILE" <<EOF
model_list:
  - model_name: claude-3-5-sonnet-20240620
    litellm_params: &local_llama
      model: openai/${BACKEND_MODEL}
      api_base: ${BACKEND_BASE}
      api_key: dummy
  - model_name: claude-3-5-sonnet-20241022
    litellm_params: *local_llama
  - model_name: claude-3-opus-20240229
    litellm_params: *local_llama
  - model_name: claude-sonnet-4-5-20250929
    litellm_params: *local_llama
  - model_name: claude-haiku-4-5-20251001
    litellm_params: *local_llama
  - model_name: claude-sonnet-4-5
    litellm_params: *local_llama
  - model_name: sonnet
    litellm_params: *local_llama
general_settings:
  master_key: ${MASTER_KEY}
litellm_settings:
  drop_params: true
EOF
fi

if port_open 127.0.0.1 "$LITELLM_PORT"; then
  log "LiteLLM already listening on 127.0.0.1:${LITELLM_PORT}; skipping start."
else
  log "Starting LiteLLM on ${LITELLM_HOST}:${LITELLM_PORT} (config: ${CONFIG_FILE})"
  run_as_user "$LITELLM_USER" bash -lc \
    "set -eu; export PATH=\"\$HOME/.local/bin:\$PATH\"; nohup litellm --host '${LITELLM_HOST}' --port '${LITELLM_PORT}' --config '${CONFIG_FILE}' >'${LITELLM_LOG_FILE}' 2>&1 &"
fi

if port_open 127.0.0.1 "$PROXY_PORT"; then
  log "Proxy already listening on 127.0.0.1:${PROXY_PORT}; skipping start."
else
  if [[ ! -f "$PROXY_SCRIPT" ]]; then
    warn "Proxy script not found: ${PROXY_SCRIPT}"
    exit 0
  fi
  log "Starting telemetry proxy on 0.0.0.0:${PROXY_PORT} -> LiteLLM http://127.0.0.1:${LITELLM_PORT}"
  run_as_user "$LITELLM_USER" bash -lc \
    "set -eu; export PORT='${PROXY_PORT}'; export LITELLM_URL='http://127.0.0.1:${LITELLM_PORT}'; nohup '${PROXY_PYTHON}' -u '${PROXY_SCRIPT}' >'${PROXY_LOG_FILE}' 2>&1 &"
fi

log "Ready:"
log "  - LiteLLM: http://127.0.0.1:${LITELLM_PORT} (requires x-api-key: ${MASTER_KEY})"
log "  - Claude bridge: http://127.0.0.1:${PROXY_PORT} (set ANTHROPIC_BASE_URL here)"
