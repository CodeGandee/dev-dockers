#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Optional auto-launch for llama.cpp OpenAI-compatible server(s).
"$SCRIPT_DIR/check-and-run-llama-cpp.sh"

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec /bin/bash

