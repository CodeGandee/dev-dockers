#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ -z "${PEI_STAGE_DIR_1:-}" ]]; then
  echo "Error: PEI_STAGE_DIR_1 is not set" >&2
  exit 1
fi

"${PEI_STAGE_DIR_1}/system/uv/install-uv.sh" --user peid --pypi-repo tuna

