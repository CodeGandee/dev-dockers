#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Bootstrapping all models..."

# Fan-out to subdirectories
for d in "${SCRIPT_DIR}"/*/; do
  if [[ -f "${d}bootstrap.sh" ]]; then
    echo ">> Bootstrapping $(basename "${d}")"
    bash "${d}bootstrap.sh"
  fi
done

echo "All models bootstrapped."
