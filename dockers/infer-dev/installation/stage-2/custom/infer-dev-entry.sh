#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

LLAMA_CPP_HELPER="$SCRIPT_DIR/check-and-run-llama-cpp.sh"
LLAMA_CPP_PKG_INSTALLER="$SCRIPT_DIR/install-llama-cpp-pkg.sh"

VLLM_HELPER="$SCRIPT_DIR/check-and-run-vllm.sh"
VLLM_OFFLINE_INSTALLER="$SCRIPT_DIR/install-vllm-offline.sh"

LITELLM_HELPER="/pei-from-host/stage-2/custom/check-and-run-litellm.sh"
LITELLM_PROXY="/pei-from-host/stage-2/system/litellm/proxy.py"

GET_PKG_ON_BOOT="${AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT:-0}"
case "${GET_PKG_ON_BOOT,,}" in
  1|true)
    # Optional: install a prebuilt llama.cpp package on container boot.
    # This must run BEFORE we create convenience symlinks, since the install replaces /soft/app/llama-cpp.
    if [[ -n "${AUTO_INFER_LLAMA_CPP_PKG_PATH:-}" ]]; then
      if [[ -x "$LLAMA_CPP_PKG_INSTALLER" ]]; then
        "$LLAMA_CPP_PKG_INSTALLER"
      else
        echo "[infer-dev-entry] Warning: installer not found or not executable: $LLAMA_CPP_PKG_INSTALLER" >&2
      fi
    fi
    ;;
  0|false|'')
    ;;
  *)
    echo "[infer-dev-entry] Warning: AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT='${AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT}' not understood; treating as false." >&2
    ;;
esac

# Convenience: expose helper under /soft/app so users can easily run it after boot.
# /soft/app is a PeiDocker "soft path" that is always present.
mkdir -p /soft/app/llama-cpp
ln -sf "$LLAMA_CPP_HELPER" /soft/app/llama-cpp/check-and-run-llama-cpp.sh
ln -sf "$LLAMA_CPP_PKG_INSTALLER" /soft/app/llama-cpp/install-llama-cpp-pkg.sh
ln -sf "$LLAMA_CPP_PKG_INSTALLER" /soft/app/llama-cpp/get-llama-cpp-pkg.sh

# Convenience: expose vLLM helpers under /soft/app.
mkdir -p /soft/app/vllm
if [[ -f "$VLLM_HELPER" ]]; then
  ln -sf "$VLLM_HELPER" /soft/app/vllm/check-and-run-vllm.sh
fi
if [[ -f "$VLLM_OFFLINE_INSTALLER" ]]; then
  ln -sf "$VLLM_OFFLINE_INSTALLER" /soft/app/vllm/install-vllm-offline.sh
fi

# Convenience: expose LiteLLM bridge helpers under /soft/app.
mkdir -p /soft/app/litellm
if [[ -f "$LITELLM_HELPER" ]]; then
  ln -sf "$LITELLM_HELPER" /soft/app/litellm/check-and-run-litellm.sh
fi
if [[ -f "$LITELLM_PROXY" ]]; then
  ln -sf "$LITELLM_PROXY" /soft/app/litellm/proxy.py
fi

# Auto-launch is gated by AUTO_INFER_LLAMA_CPP_ON_BOOT (default: off).
# AUTO_INFER_LLAMA_CPP_CONFIG alone should NOT trigger auto serving.
ON_BOOT="${AUTO_INFER_LLAMA_CPP_ON_BOOT:-0}"
case "${ON_BOOT,,}" in
  1|true)
    if [[ -n "${AUTO_INFER_LLAMA_CPP_CONFIG:-}" ]]; then
      "$LLAMA_CPP_HELPER"
    fi
    ;;
  0|false|'')
    ;;
  *)
    echo "[infer-dev-entry] Warning: AUTO_INFER_LLAMA_CPP_ON_BOOT='${AUTO_INFER_LLAMA_CPP_ON_BOOT}' not understood; treating as false." >&2
    ;;
esac

# Optional: install an offline vLLM bundle on container boot.
VLLM_BUNDLE_ON_BOOT="${AUTO_INFER_VLLM_BUNDLE_ON_BOOT:-0}"
case "${VLLM_BUNDLE_ON_BOOT,,}" in
  1|true)
    if [[ -x "$VLLM_OFFLINE_INSTALLER" ]]; then
      "$VLLM_OFFLINE_INSTALLER"
    else
      echo "[infer-dev-entry] Warning: installer not found or not executable: $VLLM_OFFLINE_INSTALLER" >&2
    fi
    ;;
  0|false|'')
    ;;
  *)
    echo "[infer-dev-entry] Warning: AUTO_INFER_VLLM_BUNDLE_ON_BOOT='${AUTO_INFER_VLLM_BUNDLE_ON_BOOT}' not understood; treating as false." >&2
    ;;
esac

# Auto-launch vLLM is gated by AUTO_INFER_VLLM_ON_BOOT (default: off).
# AUTO_INFER_VLLM_CONFIG alone should NOT trigger auto serving.
VLLM_ON_BOOT="${AUTO_INFER_VLLM_ON_BOOT:-0}"
case "${VLLM_ON_BOOT,,}" in
  1|true)
    if [[ -n "${AUTO_INFER_VLLM_CONFIG:-}" ]]; then
      "$VLLM_HELPER"
    fi
    ;;
  0|false|'')
    ;;
  *)
    echo "[infer-dev-entry] Warning: AUTO_INFER_VLLM_ON_BOOT='${AUTO_INFER_VLLM_ON_BOOT}' not understood; treating as false." >&2
    ;;
esac

# Start LiteLLM + proxy if enabled.
if [[ -x "$LITELLM_HELPER" ]]; then
  "$LITELLM_HELPER"
fi

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec /bin/bash
