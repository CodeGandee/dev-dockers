#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[sglang-offline] $*"
}

warn() {
  echo "[sglang-offline] Warning: $*" >&2
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

download_pixi_unpack_if_needed() {
  local dst="$1"

  if [[ -x "$dst" ]]; then
    return 0
  fi

  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "x86_64" ]]; then
    warn "pixi-unpack auto-download only supports x86_64 (got: $arch). Set AUTO_INFER_SGLANG_PIXI_UNPACK_BIN manually."
    return 1
  fi

  mkdir -p "$(dirname "$dst")"
  log "Downloading pixi-unpack to: $dst"
  # pixi-unpack is published by Quantco/pixi-pack.
  # See: https://pixi.prefix.dev/latest/deployment/pixi_pack/#pixi-unpack-unpacking-an-environment
  curl -fsSL "https://github.com/Quantco/pixi-pack/releases/latest/download/pixi-unpack-x86_64-unknown-linux-musl" -o "$dst"
  chmod +x "$dst"
}

BUNDLE_PATH="${AUTO_INFER_SGLANG_BUNDLE_PATH:-}"
if [[ -z "$BUNDLE_PATH" ]]; then
  exit 0
fi
if [[ ! -f "$BUNDLE_PATH" ]]; then
  warn "Bundle not found: $BUNDLE_PATH"
  exit 0
fi

SGLANG_USER="${AUTO_INFER_SGLANG_USER:-me}"
PROJECT_DIR="${AUTO_INFER_SGLANG_PROJECT_DIR:-/hard/volume/workspace/sglang-pixi-offline}"

EXPECTED_SHA256="${AUTO_INFER_SGLANG_BUNDLE_SHA256:-}"
ACTUAL_SHA256=""
if ACTUAL_SHA256="$(sha256_file "$BUNDLE_PATH" 2>/dev/null)"; then
  :
else
  warn "No sha256 tool available; skipping checksum and idempotency checks."
  ACTUAL_SHA256=""
fi

if [[ -n "$EXPECTED_SHA256" && -n "$ACTUAL_SHA256" ]]; then
  if [[ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]]; then
    echo "[sglang-offline] Error: bundle sha256 mismatch" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA256" >&2
    exit 1
  fi
fi

MARKER_FILE="$PROJECT_DIR/.installed-from.json"
ENV_DIR="$PROJECT_DIR/env"
ENV_PY="$ENV_DIR/bin/python"

if [[ -n "$ACTUAL_SHA256" && -f "$MARKER_FILE" && -x "$ENV_PY" ]]; then
  if python3 - "$MARKER_FILE" "$ACTUAL_SHA256" <<'PY'
import json
import sys

marker_path = sys.argv[1]
want_sha = sys.argv[2]

try:
    with open(marker_path, "r", encoding="utf-8") as f:
        marker = json.load(f)
except Exception:
    sys.exit(1)

if marker.get("bundle_sha256") != want_sha:
    sys.exit(1)

sys.exit(0)
PY
  then
    log "Already installed for sha256=$ACTUAL_SHA256."
    exit 0
  fi
fi

mkdir -p "$PROJECT_DIR"

log "Installing SGLang offline bundle:"
log "  bundle:  $BUNDLE_PATH"
log "  project: $PROJECT_DIR"
log "  user:    $SGLANG_USER"

rm -rf "$ENV_DIR" "$PROJECT_DIR/activate.sh" 2>/dev/null || true

case "$(basename -- "$BUNDLE_PATH")" in
  *.sh)
    run_as_user "$SGLANG_USER" bash -lc "
      set -euo pipefail
      cd \"${PROJECT_DIR}\"
      cp -f \"${BUNDLE_PATH}\" ./_bundle.sh
      chmod +x ./_bundle.sh
      ./_bundle.sh
      rm -f ./_bundle.sh
    "
    ;;
  *.tar|*.tar.gz|*.tgz)
    PIXI_UNPACK_BIN="${AUTO_INFER_SGLANG_PIXI_UNPACK_BIN:-}"
    if [[ -z "$PIXI_UNPACK_BIN" ]]; then
      PIXI_UNPACK_BIN="$(command -v pixi-unpack 2>/dev/null || true)"
    fi
    if [[ -z "$PIXI_UNPACK_BIN" ]]; then
      PIXI_UNPACK_BIN="$PROJECT_DIR/.cache/pixi-pack/pixi-unpack-x86_64-unknown-linux-musl"
      if ! download_pixi_unpack_if_needed "$PIXI_UNPACK_BIN"; then
        echo "[sglang-offline] Error: pixi-unpack not available and auto-download failed." >&2
        echo "  - Provide AUTO_INFER_SGLANG_PIXI_UNPACK_BIN=/path/to/pixi-unpack, or" >&2
        echo "  - Build a self-extracting bundle on the host using:" >&2
        echo "      ./dockers/infer-dev/host-scripts/build-sglang-bundle.sh --create-executable -o dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh" >&2
        exit 1
      fi
    fi

    if [[ ! -x "$PIXI_UNPACK_BIN" ]]; then
      echo "[sglang-offline] Error: pixi-unpack not executable: $PIXI_UNPACK_BIN" >&2
      exit 1
    fi

    run_as_user "$SGLANG_USER" bash -lc "
      set -euo pipefail
      cd \"${PROJECT_DIR}\"
      \"${PIXI_UNPACK_BIN}\" \"${BUNDLE_PATH}\"
    "
    ;;
  *)
    echo "[sglang-offline] Error: unsupported bundle extension: $BUNDLE_PATH" >&2
    echo "  Supported: .sh (self-extracting), .tar/.tar.gz/.tgz (pixi-pack archive)" >&2
    exit 1
    ;;
esac

if [[ ! -x "$ENV_PY" ]]; then
  echo "[sglang-offline] Error: expected python not found after install: $ENV_PY" >&2
  exit 1
fi

log "Verifying imports..."
run_as_user "$SGLANG_USER" "$ENV_PY" -c 'import torch, sglang; print("torch", torch.__version__, "cuda", torch.version.cuda, "cuda_available", torch.cuda.is_available()); print("sglang", getattr(sglang, "__version__", "unknown"))'

python3 - "$MARKER_FILE" "$BUNDLE_PATH" "$ACTUAL_SHA256" <<'PY'
import json
import os
import sys
import time

marker_path = sys.argv[1]
bundle_path = sys.argv[2]
bundle_sha = sys.argv[3]

payload = {
    "bundle_path": bundle_path,
    "bundle_sha256": bundle_sha,
    "installed_at_unix": int(time.time()),
}
os.makedirs(os.path.dirname(marker_path), exist_ok=True)
with open(marker_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
    f.write("\n")
PY

log "Offline install complete."

