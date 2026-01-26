#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${PROJECT_DIR}/../../../.." && pwd)"

MODEL_DIR_DEFAULT="${REPO_ROOT}/models/qwen2-vl-7b/source-data"
MODEL_DIR="${SGLANG_MODEL_DIR:-${MODEL_DIR_DEFAULT}}"

SERVED_MODEL_NAME="${SGLANG_SERVED_MODEL_NAME:-qwen2-vl-7b}"

HOST="${SGLANG_HOST:-127.0.0.1}"
READY_HOST="${SGLANG_READY_HOST:-127.0.0.1}"

PORT="${SGLANG_PORT:-$((30000 + RANDOM % 10000))}"
STARTUP_TIMEOUT_SECS="${SGLANG_STARTUP_TIMEOUT_SECS:-900}"

TP_SIZE="${SGLANG_TP_SIZE:-1}"
DEVICE="${SGLANG_DEVICE:-cuda}"

# SGLang blocks torch==2.9.1 with CuDNN < 9.15 (PyTorch wheels pin cudnn 9.10.x).
# For local/offline smoke testing, allow bypassing this check.
SGLANG_DISABLE_CUDNN_CHECK="${SGLANG_DISABLE_CUDNN_CHECK:-1}"
export SGLANG_DISABLE_CUDNN_CHECK

if [[ ! -d "${MODEL_DIR}" ]]; then
  echo "ERROR: model dir not found: ${MODEL_DIR}" >&2
  echo "Set SGLANG_MODEL_DIR to override (default: ${MODEL_DIR_DEFAULT})." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required for the smoke test." >&2
  exit 1
fi

log_file="$(mktemp -t "sglang-default-qwen2-vl-7b.XXXXXX.log")"

echo
echo "=== SGLang smoke test (cu128 default env) ==="
echo "Model dir: ${MODEL_DIR}"
echo "Served model: ${SERVED_MODEL_NAME}"
echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo "TP size: ${TP_SIZE}"
echo "Device: ${DEVICE}"
echo "Log file: ${log_file}"

pixi run python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available())"
pixi run python -c "import sglang; print('sglang', getattr(sglang, '__version__', 'unknown'))"
pixi run python -c "import torch; print('device_count', torch.cuda.device_count() if torch.cuda.is_available() else 0)"

pixi run python -m sglang.launch_server \
  --model-path "${MODEL_DIR}" \
  --served-model-name "${SERVED_MODEL_NAME}" \
  --enable-multimodal \
  --trust-remote-code \
  --skip-server-warmup \
  --device "${DEVICE}" \
  --tensor-parallel-size "${TP_SIZE}" \
  --host "${HOST}" \
  --port "${PORT}" \
  >"${log_file}" 2>&1 &
server_pid="$!"

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
trap cleanup EXIT

deadline_ts="$(( $(date +%s) + STARTUP_TIMEOUT_SECS ))"
while true; do
  if curl -fsS "http://${READY_HOST}:${PORT}/v1/models" | grep -q "\"${SERVED_MODEL_NAME}\""; then
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

req_json="$(cat <<JSON
{
  "model": "${SERVED_MODEL_NAME}",
  "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
  "max_tokens": 64,
  "temperature": 0
}
JSON
)"

resp="$(curl -fsS "http://${READY_HOST}:${PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "${req_json}")"

echo
echo "=== Request ==="
echo "${req_json}"

echo
echo "=== Response ==="
echo "${resp}"

printf '%s' "${resp}" | pixi run python -c "\
import json, sys; \
j = json.load(sys.stdin); \
choices = j.get('choices') or []; \
assert choices, 'ERROR: response missing choices'; \
msg = choices[0].get('message') or {}; \
content = msg.get('content'); \
assert content, 'ERROR: response missing message.content'; \
print('OK: got message.content:', str(content)[:200])"

echo
echo "Smoke test passed."
