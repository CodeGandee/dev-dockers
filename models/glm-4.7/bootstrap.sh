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
TARGET="/data2/huangzhe/llm-models/GLM-4.7-GGUF"

echo "Bootstrapping GLM-4.7 GGUF in ${REF_DIR} ..."

if [[ ! -d "$TARGET" ]]; then
    echo "Error: Target directory $TARGET does not exist."
    exit 1
fi

rm -rf "${SRC_LINK}"
ln -s "${TARGET}" "${SRC_LINK}"

echo "Linked source-data -> ${TARGET}"
echo "Done."
