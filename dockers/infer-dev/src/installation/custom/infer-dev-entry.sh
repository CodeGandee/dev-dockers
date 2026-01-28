#!/usr/bin/env bash
set -euo pipefail

# NOTE:
# This file exists to satisfy PeiDocker's host-side script existence checks.
# The actual stage-2 entry script that runs in the container lives at:
#   installation/stage-2/custom/infer-dev-entry.sh

exec /bin/bash

