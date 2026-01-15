#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

LLAMA_CPP_HELPER="$SCRIPT_DIR/check-and-run-llama-cpp.sh"
LLAMA_CPP_PKG_INSTALLER="$SCRIPT_DIR/install-llama-cpp-pkg.sh"

# Optional: install a prebuilt llama.cpp package on container boot.
# This must run BEFORE we create convenience symlinks, since the install replaces /soft/app/llama-cpp.
if [[ -n "${AUTO_INFER_LLAMA_CPP_PKG_PATH:-}" ]]; then
  if [[ -x "$LLAMA_CPP_PKG_INSTALLER" ]]; then
    "$LLAMA_CPP_PKG_INSTALLER"
  else
    echo "[infer-dev-entry] Warning: installer not found or not executable: $LLAMA_CPP_PKG_INSTALLER" >&2
  fi
fi

# Convenience: expose helper under /soft/app so users can easily run it after boot.
# /soft/app is a PeiDocker "soft path" that is always present.
mkdir -p /soft/app/llama-cpp
ln -sf "$LLAMA_CPP_HELPER" /soft/app/llama-cpp/check-and-run-llama-cpp.sh

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

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec /bin/bash
