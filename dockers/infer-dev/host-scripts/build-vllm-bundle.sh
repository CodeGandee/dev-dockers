#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build-vllm-bundle.sh [OPTIONS]

Build a vLLM offline bundle tar using Pixi + pixi-pack.

Outputs a tar archive containing:
  - channel/ (linux-64 + noarch packages + repodata.json)
  - environment.yml
  - pixi-pack.json

Options:
  --template-dir <dir>          Pixi project dir to pack
                                (default: dockers/infer-dev/src/installation/stage-2/utilities/vllm-pixi-template)
  -o, --output-file <path>      Output tar file path
                                (default: dockers/infer-dev/.container/workspace/vllm-offline-bundle.tar)
  -p, --platform <platform>     Platform to pack (default: linux-64)
  -e, --environment <env>       Pixi environment name to pack (default: default)
      --rattler-config <path>   Optional rattler config TOML (mirrors, etc) passed to pixi-pack (-c)
      --rattler-cache-dir <dir> Pixi/Rattler cache dir (sets RATTLER_CACHE_DIR)
                                (default: dockers/infer-dev/.container/workspace/.cache/rattler/cache)
      --pixi-pack-cache-dir <d> pixi-pack cache dir (passed to --use-cache)
                                (default: dockers/infer-dev/.container/workspace/.cache/pixi-pack)
      --retries <n>             pixi-pack retries on transient download errors (default: 5)
      --retry-sleep <sec>       Sleep between retries (default: 5)
      --skip-verify             Skip 'pixi run verify' before packing
  -h, --help                    Show this help

Notes:
  - Proxy is taken from standard env vars: http_proxy / https_proxy.
  - The vLLM template includes [system-requirements] cuda=... so Pixi can solve CUDA builds.
USAGE
}

redact_url() {
  # Redact credentials in http(s)://user:pass@host:port
  # shellcheck disable=SC2001
  echo "$1" | sed -E 's#(https?://)[^/@:]+:[^/@]+@#\\1***:***@#'
}

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INFER_DEV_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

TEMPLATE_DIR_DEFAULT="$INFER_DEV_DIR/installation/stage-2/utilities/vllm-pixi-template"
OUTPUT_FILE_DEFAULT="$INFER_DEV_DIR/.container/workspace/vllm-offline-bundle.tar"
PLATFORM_DEFAULT="linux-64"
ENVIRONMENT_DEFAULT="default"
RATTLER_CACHE_DIR_DEFAULT="$INFER_DEV_DIR/.container/workspace/.cache/rattler/cache"
PIXI_PACK_CACHE_DIR_DEFAULT="$INFER_DEV_DIR/.container/workspace/.cache/pixi-pack"

TEMPLATE_DIR="$TEMPLATE_DIR_DEFAULT"
OUTPUT_FILE="$OUTPUT_FILE_DEFAULT"
PLATFORM="$PLATFORM_DEFAULT"
ENVIRONMENT="$ENVIRONMENT_DEFAULT"
RATTLER_CACHE_DIR="$RATTLER_CACHE_DIR_DEFAULT"
PIXI_PACK_CACHE_DIR="$PIXI_PACK_CACHE_DIR_DEFAULT"
RATTLER_CONFIG=""
RETRIES=5
RETRY_SLEEP=5
SKIP_VERIFY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template-dir)
      TEMPLATE_DIR="${2:-}"; shift 2 ;;
    -o|--output-file)
      OUTPUT_FILE="${2:-}"; shift 2 ;;
    -p|--platform)
      PLATFORM="${2:-}"; shift 2 ;;
    -e|--environment)
      ENVIRONMENT="${2:-}"; shift 2 ;;
    --rattler-config)
      RATTLER_CONFIG="${2:-}"; shift 2 ;;
    --rattler-cache-dir)
      RATTLER_CACHE_DIR="${2:-}"; shift 2 ;;
    --pixi-pack-cache-dir)
      PIXI_PACK_CACHE_DIR="${2:-}"; shift 2 ;;
    --retries)
      RETRIES="${2:-}"; shift 2 ;;
    --retry-sleep)
      RETRY_SLEEP="${2:-}"; shift 2 ;;
    --skip-verify)
      SKIP_VERIFY=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! command -v pixi >/dev/null 2>&1; then
  echo "Error: pixi not found in PATH" >&2
  exit 1
fi
if ! command -v pixi-pack >/dev/null 2>&1; then
  echo "Error: pixi-pack not found in PATH (try: pixi global install pixi-pack)" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_DIR/pixi.toml" ]]; then
  echo "Error: pixi.toml not found under template dir: $TEMPLATE_DIR" >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE_DIR/pixi.lock" ]]; then
  echo "Error: pixi.lock not found under template dir: $TEMPLATE_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p "$RATTLER_CACHE_DIR"
mkdir -p "$PIXI_PACK_CACHE_DIR"
mkdir -p "$INFER_DEV_DIR/.container/workspace/.tmp"

HTTP_PROXY_RAW="${http_proxy:-${HTTP_PROXY:-}}"
HTTPS_PROXY_RAW="${https_proxy:-${HTTPS_PROXY:-}}"

echo "[build-vllm-bundle] infer-dev: $INFER_DEV_DIR"
echo "[build-vllm-bundle] template:  $TEMPLATE_DIR"
echo "[build-vllm-bundle] output:    $OUTPUT_FILE"
echo "[build-vllm-bundle] platform:   $PLATFORM"
echo "[build-vllm-bundle] env:        $ENVIRONMENT"
echo "[build-vllm-bundle] RATTLER_CACHE_DIR=$(redact_url "$RATTLER_CACHE_DIR")"
echo "[build-vllm-bundle] pixi-pack cache:  $(redact_url "$PIXI_PACK_CACHE_DIR")"
if [[ -n "$RATTLER_CONFIG" ]]; then
  echo "[build-vllm-bundle] rattler config:  $RATTLER_CONFIG"
fi
if [[ -n "$HTTP_PROXY_RAW" ]]; then
  echo "[build-vllm-bundle] http_proxy=$(redact_url "$HTTP_PROXY_RAW")"
fi
if [[ -n "$HTTPS_PROXY_RAW" ]]; then
  echo "[build-vllm-bundle] https_proxy=$(redact_url "$HTTPS_PROXY_RAW")"
fi

export RATTLER_CACHE_DIR

WORK_DIR="$(mktemp -d "$INFER_DEV_DIR/.container/workspace/.tmp/vllm-pixi-template.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cp -f "$TEMPLATE_DIR/pixi.toml" "$WORK_DIR/pixi.toml"
cp -f "$TEMPLATE_DIR/pixi.lock" "$WORK_DIR/pixi.lock"

echo "[build-vllm-bundle] pixi lock ..."
pixi lock --manifest-path "$WORK_DIR"
if ! cmp -s "$WORK_DIR/pixi.lock" "$TEMPLATE_DIR/pixi.lock"; then
  echo "[build-vllm-bundle] Updating template pixi.lock (keeps template dir free of .pixi/ binaries)..."
  cp -f "$WORK_DIR/pixi.lock" "$TEMPLATE_DIR/pixi.lock"
fi

if [[ "$SKIP_VERIFY" -ne 1 ]]; then
  echo "[build-vllm-bundle] pixi run verify ..."
  pixi run --manifest-path "$WORK_DIR" --frozen verify
fi

echo "[build-vllm-bundle] pixi-pack ..."
PIXI_PACK_ARGS=( -p "$PLATFORM" -e "$ENVIRONMENT" --use-cache "$PIXI_PACK_CACHE_DIR" -o "$OUTPUT_FILE" )
if [[ -n "$RATTLER_CONFIG" ]]; then
  PIXI_PACK_ARGS+=( -c "$RATTLER_CONFIG" )
fi
PIXI_PACK_ARGS+=( "$WORK_DIR" )

attempt=1
while true; do
  rm -f "$OUTPUT_FILE" 2>/dev/null || true
  if pixi-pack "${PIXI_PACK_ARGS[@]}"; then
    break
  fi
  if [[ "$attempt" -ge "$RETRIES" ]]; then
    echo "[build-vllm-bundle] Error: pixi-pack failed after $attempt attempt(s)." >&2
    exit 1
  fi
  echo "[build-vllm-bundle] Warning: pixi-pack failed (attempt $attempt/$RETRIES); retrying after ${RETRY_SLEEP}s..." >&2
  sleep "$RETRY_SLEEP"
  attempt=$((attempt + 1))
done

echo "[build-vllm-bundle] done: $OUTPUT_FILE"
