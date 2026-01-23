#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${PROJECT_DIR}/../../../.." && pwd)"

MODEL_DIR_DEFAULT="${REPO_ROOT}/models/qwen2-vl-7b/source-data"
MODEL_DIR="${SGLANG_MODEL_DIR:-${MODEL_DIR_DEFAULT}}"

SERVED_MODEL_NAME="${SGLANG_SERVED_MODEL_NAME:-qwen2-vl-7b}"

HOST="${SGLANG_HOST:-0.0.0.0}"
READY_HOST="${SGLANG_READY_HOST:-127.0.0.1}"

BASE_PORT="${SGLANG_BASE_PORT:-30100}"
STARTUP_TIMEOUT_SECS="${SGLANG_STARTUP_TIMEOUT_SECS:-900}"

TP_SIZE_CU126="${SGLANG_TP_SIZE_CU126:-1}"
TP_SIZE_CU128="${SGLANG_TP_SIZE_CU128:-1}"

RUN_MODE="${SGLANG_RUN_MODE:-both}" # one of: cu126 | cu128 | both

if [[ ! -d "${MODEL_DIR}" ]]; then
  echo "ERROR: model dir not found: ${MODEL_DIR}" >&2
  echo "Set SGLANG_MODEL_DIR to override (default: ${MODEL_DIR_DEFAULT})." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required for the smoke test." >&2
  exit 1
fi

smoke_one_env() {
  local env_name="$1"
  local port="$2"
  local tp_size="$3"
  local log_file

  log_file="$(mktemp -t "sglang-${env_name}-qwen2-vl-7b.XXXXXX.log")"

  echo
  echo "=== SGLang smoke test: env=${env_name} port=${port} tp=${tp_size} ==="
  echo "Model dir: ${MODEL_DIR}"
  echo "Log file: ${log_file}"

  pixi run --environment "${env_name}" python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available())"
  pixi run --environment "${env_name}" python -c "import sglang; print('sglang', getattr(sglang, '__version__', 'unknown'))"

  # Start server in background and capture logs.
  pixi run --environment "${env_name}" python -m sglang.launch_server \
    --model-path "${MODEL_DIR}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --enable-multimodal \
    --trust-remote-code \
    --tensor-parallel-size "${tp_size}" \
    --host "${HOST}" \
    --port "${port}" \
    >"${log_file}" 2>&1 &
  local server_pid="$!"

  cleanup() {
    if kill -0 "${server_pid}" >/dev/null 2>&1; then
      kill "${server_pid}" >/dev/null 2>&1 || true
      for _ in $(seq 1 30); do
        if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      kill -9 "${server_pid}" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup RETURN

  # Wait for readiness.
  local deadline_ts
  deadline_ts="$(( $(date +%s) + STARTUP_TIMEOUT_SECS ))"
  while true; do
    if curl -fsS "http://${READY_HOST}:${port}/v1/models" | grep -q "\"${SERVED_MODEL_NAME}\""; then
      break
    fi

    if [[ "$(date +%s)" -ge "${deadline_ts}" ]]; then
      echo "ERROR: server did not become ready within ${STARTUP_TIMEOUT_SECS}s." >&2
      echo "Last ~200 log lines (${log_file}):" >&2
      tail -n 200 "${log_file}" >&2 || true
      exit 1
    fi
    sleep 2
  done

  # Send one real request.
  local resp
  resp="$(curl -fsS "http://${READY_HOST}:${port}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{
      \"model\": \"${SERVED_MODEL_NAME}\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one short sentence.\"}],
      \"max_tokens\": 64,
      \"temperature\": 0
    }")"

  echo
  echo "=== Response (${env_name}) ==="
  echo "${resp}"

  printf '%s' "${resp}" | pixi run --environment "${env_name}" python -c "\
import json, sys; \
j = json.load(sys.stdin); \
choices = j.get('choices') or []; \
assert choices, 'ERROR: response missing choices'; \
msg = choices[0].get('message') or {}; \
content = msg.get('content'); \
assert content, 'ERROR: response missing message.content'; \
print('OK: got message.content:', str(content)[:200])"
}

case "${RUN_MODE}" in
  cu126)
    smoke_one_env default "${BASE_PORT}" "${TP_SIZE_CU126}"
    ;;
  cu128)
    smoke_one_env cu128 "$((BASE_PORT + 1))" "${TP_SIZE_CU128}"
    ;;
  both)
    smoke_one_env default "${BASE_PORT}" "${TP_SIZE_CU126}"
    smoke_one_env cu128 "$((BASE_PORT + 1))" "${TP_SIZE_CU128}"
    ;;
  *)
    echo "ERROR: invalid SGLANG_RUN_MODE='${RUN_MODE}' (expected: cu126|cu128|both)" >&2
    exit 1
    ;;
esac

echo
echo "All requested smoke tests passed."
