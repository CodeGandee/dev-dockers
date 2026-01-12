#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
set -a
source "$PROJECT_DIR/merged.env"
set +a

# Normalize boolean-like values to 1/0 (accepts 1/0/true/false; case-insensitive). Empty remains empty.
normalize_bool() {
  local __val="$1"
  if [ -z "${__val+x}" ] || [ -z "$__val" ]; then
    echo "$__val"; return 0
  fi
  case "$__val" in
    1|true|TRUE|True) echo 1 ;;
    0|false|FALSE|False) echo 0 ;;
    *)
      __val_lower=$(printf '%s' "$__val" | tr '[:upper:]' '[:lower:]')
      if [ "$__val_lower" = "true" ]; then echo 1; elif [ "$__val_lower" = "false" ]; then echo 0; else echo "$__val"; fi ;;
  esac
}

CONTAINER_NAME="${RUN_CONTAINER_NAME:-pei-stage-2}"
DETACH=$(normalize_bool "${RUN_DETACH:-0}")
RM=$(normalize_bool "${RUN_REMOVE:-1}")
TTY=$(normalize_bool "${RUN_TTY:-1}")
GPU_MODE="${RUN_GPU:-auto}"
DEVICE_TYPE="${RUN_DEVICE_TYPE:-cpu}"
IMG="${STAGE2_IMAGE_NAME:-infer-dev:stage-2}"

CLI_PORTS=()
CLI_VOLS=()
POSITIONAL=()

usage() {
  cat <<'USAGE'
Usage: run-merged.sh [OPTIONS] [--] [CMD [ARGS...]]

Run the merged image with ports, volumes, and GPU options derived from merged.env.

Options:
  -n, --name <container>         Set container name (default from merged.env)
  -d, --detach                   Run in detached mode
      --no-rm                    Do not remove container on exit
      --image <name:tag>         Override image to run
  -p, --publish host:container   Publish a port (repeatable)
  -v, --volume src:dst[:mode]    Bind mount a volume (repeatable)
      --gpus auto|all|none       GPU mode (default: auto)
  -h, --help                     Show this help and exit

Pass-through:
  Use "--" to stop parsing and treat remaining arguments as CMD to run
  inside the container.

Examples:
  ./run-merged.sh
  ./run-merged.sh -d -p 8080:8080
  ./run-merged.sh -- bash -lc 'echo hello'
USAGE
}

  while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    -n|--name)
      [[ $# -ge 2 ]] || { echo "Error: --name requires a value" >&2; exit 1; }
      CONTAINER_NAME="$2"; shift 2 ;;
    -d|--detach)
      DETACH="1"; shift ;;
    --no-rm)
      RM="0"; shift ;;
    --image)
      [[ $# -ge 2 ]] || { echo "Error: --image requires a value <name:tag>" >&2; exit 1; }
      IMG="$2"; shift 2 ;;
    -p|--publish)
      [[ $# -ge 2 ]] || { echo "Error: --publish requires a value" >&2; exit 1; }
      CLI_PORTS+=("$2"); shift 2 ;;
    -v|--volume)
      [[ $# -ge 2 ]] || { echo "Error: --volume requires a value" >&2; exit 1; }
      CLI_VOLS+=("$2"); shift 2 ;;
    --gpus)
      [[ $# -ge 2 ]] || { echo "Error: --gpus requires a value" >&2; exit 1; }
      GPU_MODE="$2"; shift 2 ;;
    --)
      shift; POSITIONAL+=("$@"); break ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

cmd=( docker run )
if [[ "$DETACH" == "1" ]]; then cmd+=( -d ); else [[ "$TTY" == "1" ]] && cmd+=( -it ); fi
[[ "$RM" == "1" ]] && cmd+=( --rm )
[[ -n "${RUN_NETWORK:-}" ]] && cmd+=( --network "$RUN_NETWORK" )

# ports
for p in $RUN_PORTS; do [[ -n "$p" ]] && cmd+=( -p "$p" ); done
for p in "${CLI_PORTS[@]}"; do [[ -n "$p" ]] && cmd+=( -p "$p" ); done

# volumes
for v in $RUN_VOLUMES; do [[ -n "$v" ]] && cmd+=( -v "$v" ); done
for v in "${CLI_VOLS[@]}"; do [[ -n "$v" ]] && cmd+=( -v "$v" ); done

# extra hosts
for h in $RUN_EXTRA_HOSTS; do [[ -n "$h" ]] && cmd+=( --add-host "$h" ); done

# gpus
if [[ "$GPU_MODE" == "all" ]]; then cmd+=( --gpus all );
elif [[ "$GPU_MODE" == "auto" && "$DEVICE_TYPE" == "gpu" ]]; then cmd+=( --gpus all ); fi

# env vars
if [[ "$(normalize_bool "${RUN_ENV_ENABLE:-0}")" == "1" ]]; then
  for pair in $RUN_ENV_VARS; do [[ -n "$pair" ]] && cmd+=( -e "$pair" ); done
fi

cmd+=( --name "$CONTAINER_NAME" )
[[ -n "${RUN_EXTRA_ARGS:-}" ]] && cmd+=( $RUN_EXTRA_ARGS )

cmd+=( "$IMG" )
[[ ${#POSITIONAL[@]} -gt 0 ]] && cmd+=( "${POSITIONAL[@]}" )

printf '%q ' "${cmd[@]}"; echo
exec "${cmd[@]}"
