#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="${SCRIPT_DIR}"

require_cmd() {
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "missing required command: $c" >&2
      exit 127
    fi
  done
}

require_cmd ln

SRC_LINK="${REF_DIR}/source-data"
TARGET="/data1/huangzhe/llm-models/qwen3-0.6b/qwen/Qwen3-0___6B"

echo "Bootstrapping Qwen3 0.6B in ${REF_DIR} ..."

if [[ ! -d "$TARGET" ]]; then
    echo "Error: Target directory $TARGET does not exist."
    exit 1
fi

rm -rf "${SRC_LINK}"
ln -s "${TARGET}" "${SRC_LINK}"

echo "Linked source-data -> ${TARGET}"
echo "Done."
