#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[vllm-offline] $*"
}

warn() {
  echo "[vllm-offline] Warning: $*" >&2
}

normalize_bool() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo ""
    return 0
  fi
  case "${val,,}" in
    1|true) echo 1 ;;
    0|false) echo 0 ;;
    *) echo "$val" ;;
  esac
}

run_as_user() {
  local user="$1"
  shift

  if [[ -z "$user" || "$user" == "$(whoami)" ]]; then
    "$@"
    return 0
  fi

  if [[ "$(whoami)" != "root" ]]; then
    warn "Cannot switch to user '$user' (not root). Running as $(whoami)."
    "$@"
    return 0
  fi

  if ! id -u "$user" >/dev/null 2>&1; then
    warn "User '$user' does not exist. Running as root."
    "$@"
    return 0
  fi

  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    su -l "$user" -c "$(printf '%q ' "$@")"
  fi
}

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    return 1
  fi
}

BUNDLE_PATH="${AUTO_INFER_VLLM_BUNDLE_PATH:-}"
if [[ -z "$BUNDLE_PATH" ]]; then
  exit 0
fi
if [[ ! -f "$BUNDLE_PATH" ]]; then
  warn "Bundle not found: $BUNDLE_PATH"
  exit 0
fi

VLLM_USER="${AUTO_INFER_VLLM_USER:-me}"
PROJECT_DIR="${AUTO_INFER_VLLM_PIXI_PROJECT_DIR:-/hard/volume/workspace/vllm-pixi-offline}"
ENVIRONMENT="${AUTO_INFER_VLLM_PIXI_ENVIRONMENT:-default}"
TEMPLATE_DIR="${AUTO_INFER_VLLM_PIXI_TEMPLATE_DIR:-/pei-from-host/stage-2/utilities/vllm-pixi-template}"

EXPECTED_SHA256="${AUTO_INFER_VLLM_BUNDLE_SHA256:-}"
ACTUAL_SHA256=""
if ACTUAL_SHA256="$(sha256_file "$BUNDLE_PATH" 2>/dev/null)"; then
  :
else
  warn "No sha256 tool available; skipping checksum and idempotency checks."
  ACTUAL_SHA256=""
fi

if [[ -n "$EXPECTED_SHA256" && -n "$ACTUAL_SHA256" ]]; then
  if [[ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]]; then
    echo "[vllm-offline] Error: bundle sha256 mismatch" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA256" >&2
    exit 1
  fi
fi

MARKER_FILE="$PROJECT_DIR/.installed-from.json"
if [[ -n "$ACTUAL_SHA256" && -f "$MARKER_FILE" ]]; then
  if python3 - "$MARKER_FILE" "$ACTUAL_SHA256" "$ENVIRONMENT" <<'PY'
import json
import os
import sys

marker_path = sys.argv[1]
want_sha = sys.argv[2]
env_name = sys.argv[3]

try:
    with open(marker_path, "r", encoding="utf-8") as f:
        marker = json.load(f)
except Exception:
    sys.exit(1)

got_sha = marker.get("bundle_sha256")
if got_sha != want_sha:
    sys.exit(1)

project_dir = os.path.dirname(marker_path)
env_python = os.path.join(project_dir, ".pixi", "envs", env_name, "bin", "python")
if not os.path.isfile(env_python):
    sys.exit(1)

sys.exit(0)
PY
  then
    log "Already installed for sha256=$ACTUAL_SHA256 (env: $ENVIRONMENT)."
    exit 0
  fi
fi

if [[ ! -f "$TEMPLATE_DIR/pixi.toml" || ! -f "$TEMPLATE_DIR/pixi.lock" ]]; then
  echo "[vllm-offline] Error: template missing pixi.toml/pixi.lock under: $TEMPLATE_DIR" >&2
  exit 1
fi

log "Installing vLLM offline bundle:"
log "  bundle:  $BUNDLE_PATH"
log "  project: $PROJECT_DIR"
log "  env:     $ENVIRONMENT"
log "  user:    $VLLM_USER"

export VLLM_OFFLINE_PROJECT_DIR="$PROJECT_DIR"
export VLLM_OFFLINE_BUNDLE_PATH="$BUNDLE_PATH"
export VLLM_OFFLINE_TEMPLATE_DIR="$TEMPLATE_DIR"
export VLLM_OFFLINE_ENVIRONMENT="$ENVIRONMENT"
export VLLM_OFFLINE_SHA256="$ACTUAL_SHA256"

run_as_user "$VLLM_USER" bash -lc '
  set -euo pipefail

  export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"

  mkdir -p "$VLLM_OFFLINE_PROJECT_DIR"

  # Always sync the template project files so the bundle, manifest, and lock stay consistent.
  cp -f "$VLLM_OFFLINE_TEMPLATE_DIR/pixi.toml" "$VLLM_OFFLINE_PROJECT_DIR/pixi.toml"
  cp -f "$VLLM_OFFLINE_TEMPLATE_DIR/pixi.lock" "$VLLM_OFFLINE_PROJECT_DIR/pixi.lock"

  # If re-installing, clear previous extracted channel and env.
  if [[ -d "$VLLM_OFFLINE_PROJECT_DIR/channel" ]]; then
    rm -rf "$VLLM_OFFLINE_PROJECT_DIR/channel"
  fi
  if [[ -d "$VLLM_OFFLINE_PROJECT_DIR/.pixi" ]]; then
    rm -rf "$VLLM_OFFLINE_PROJECT_DIR/.pixi"
  fi

  tar -xf "$VLLM_OFFLINE_BUNDLE_PATH" -C "$VLLM_OFFLINE_PROJECT_DIR"

  if [[ ! -d "$VLLM_OFFLINE_PROJECT_DIR/channel" ]]; then
    echo "[vllm-offline] Error: bundle did not create channel/ under $VLLM_OFFLINE_PROJECT_DIR" >&2
    exit 1
  fi

  # Patch channels to local-only so installs are offline.
  if grep -qE "^[[:space:]]*channels[[:space:]]*=" "$VLLM_OFFLINE_PROJECT_DIR/pixi.toml"; then
    sed -i "s#^[[:space:]]*channels[[:space:]]*=.*#channels = [\"./channel\"]#g" "$VLLM_OFFLINE_PROJECT_DIR/pixi.toml"
  else
    echo "[vllm-offline] Error: could not find channels=... in pixi.toml to patch to ./channel" >&2
    exit 1
  fi

  # Re-lock using ONLY the local channel so the lock contains local package paths
  # (pixi-pack provides channel/ + repodata.json, so this stays offline).
  pixi lock --manifest-path "$VLLM_OFFLINE_PROJECT_DIR"

  pixi install --manifest-path "$VLLM_OFFLINE_PROJECT_DIR" --environment "$VLLM_OFFLINE_ENVIRONMENT" --frozen
  pixi run --manifest-path "$VLLM_OFFLINE_PROJECT_DIR" --environment "$VLLM_OFFLINE_ENVIRONMENT" --frozen verify

  python3 - "$VLLM_OFFLINE_PROJECT_DIR/.installed-from.json" <<PY
import json
import os
import time

marker_path = os.environ["VLLM_OFFLINE_PROJECT_DIR"] + "/.installed-from.json"
payload = {
  "bundle_path": os.environ.get("VLLM_OFFLINE_BUNDLE_PATH", ""),
  "bundle_sha256": os.environ.get("VLLM_OFFLINE_SHA256", ""),
  "pixi_environment": os.environ.get("VLLM_OFFLINE_ENVIRONMENT", "default"),
  "installed_at_unix": int(time.time()),
}
with open(marker_path, "w", encoding="utf-8") as f:
  json.dump(payload, f, indent=2, sort_keys=True)
  f.write("\n")
PY
'

log "Offline install complete."
