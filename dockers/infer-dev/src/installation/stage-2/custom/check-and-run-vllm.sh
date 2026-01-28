#!/usr/bin/env bash

# check-and-run-vllm.sh
# Checks for AUTO_INFER_VLLM_CONFIG environment variable and launches vLLM API server instances via Pixi.

set -euo pipefail

log() {
  echo "[check-and-run-vllm] $*"
}

warn() {
  echo "[check-and-run-vllm] Warning: $*" >&2
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

CONFIG_VAR="AUTO_INFER_VLLM_CONFIG"
CONFIG_FILE="${!CONFIG_VAR:-}"

if [[ -z "$CONFIG_FILE" ]]; then
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  warn "Config file not found at: $CONFIG_FILE. Skipping."
  exit 0
fi

log "Found config at $CONFIG_FILE. Parsing..."

PYTHON_PARSER=$(cat <<'EOF'
import sys
import json
import os

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("Error: tomllib (Python 3.11+) or tomli not installed.", file=sys.stderr)
        sys.exit(1)

def deep_merge(target, source):
    for k, v in source.items():
        if isinstance(v, dict) and k in target and isinstance(target[k], dict):
            deep_merge(target[k], v)
        else:
            target[k] = v

def parse_toml(file_path):
    with open(file_path, "rb") as f:
        data = tomllib.load(f)

    overrides_json = os.environ.get("AUTO_INFER_VLLM_OVERRIDES")
    if overrides_json:
        try:
            overrides = json.loads(overrides_json)
            deep_merge(data, overrides)
            print(f"[check-and-run-vllm] Applied overrides: {overrides_json}", file=sys.stderr)
        except json.JSONDecodeError as e:
            print(f"[check-and-run-vllm] Failed to parse overrides JSON: {e}", file=sys.stderr)

    master = data.get("master", {})
    if not master.get("enable", True):
        print(json.dumps([]))
        return

    pixi_project_dir = master.get("pixi_project_dir") or os.environ.get("AUTO_INFER_VLLM_PIXI_PROJECT_DIR") or "/hard/volume/workspace/vllm-pixi-offline"
    pixi_environment = master.get("pixi_environment") or "default"
    api_server_module = master.get("api_server_module") or "vllm.entrypoints.openai.api_server"

    instances_data = data.get("instance", {})
    global_control = instances_data.get("control", {}) if isinstance(instances_data, dict) else {}
    global_server = instances_data.get("server", {}) if isinstance(instances_data, dict) else {}

    results = []

    for key, value in (instances_data or {}).items():
        if key in ("control", "server"):
            continue
        if not isinstance(value, dict):
            continue

        model_name = key
        model_config = value

        final_control = dict(global_control)
        final_control.update(model_config.get("control", {}))

        if not final_control.get("enabled", True):
            continue

        final_server = dict(global_server)
        model_server = model_config.get("server", {})
        for k, v in model_server.items():
            if k in final_server and isinstance(final_server[k], list) and isinstance(v, list):
                final_server[k] = final_server[k] + v
            else:
                final_server[k] = v

        cmd_args = []

        extra = final_server.pop("extra_args", [])
        if isinstance(extra, list):
            cmd_args.extend(map(str, extra))

        def format_key(k):
            return "--" + k.replace("_", "-")

        for k, v in final_server.items():
            flag = format_key(k)
            if isinstance(v, bool):
                if v:
                    cmd_args.append(flag)
            elif isinstance(v, list):
                for item in v:
                    cmd_args.append(flag)
                    cmd_args.append(str(item))
            else:
                cmd_args.append(flag)
                cmd_args.append(str(v))

        log_dir = final_control.get("log_dir", "/tmp")
        default_log = os.path.join(log_dir, f"vllm-server-{model_name}.log")
        log_file = final_control.get("log_file", default_log)

        background = final_control.get("background", True)
        gpu_ids = final_control.get("gpu_ids")

        results.append({
            "name": model_name,
            "pixi_project_dir": pixi_project_dir,
            "pixi_environment": pixi_environment,
            "api_server_module": api_server_module,
            "cmd": cmd_args,
            "log_file": log_file,
            "background": background,
            "gpu_ids": gpu_ids,
        })

    print(json.dumps(results))

if __name__ == "__main__":
    parse_toml(sys.argv[1])
EOF
)

PARSED_JSON=$(python3 -c "$PYTHON_PARSER" "$CONFIG_FILE")

VLLM_USER="${AUTO_INFER_VLLM_USER:-me}"

run_as_user "$VLLM_USER" python3 - "$PARSED_JSON" <<'PY'
import json
import os
import subprocess
import sys
import shutil

instances = json.loads(sys.argv[1])
if not instances:
    sys.exit(0)

env = os.environ.copy()
home = env.get("HOME", "")
if home:
    env["PATH"] = f"{home}/.pixi/bin:{home}/.local/bin:{env.get('PATH','')}"

pixi = shutil.which("pixi", path=env.get("PATH"))
if not pixi:
    print("[check-and-run-vllm] Error: pixi not found in PATH for current user", file=sys.stderr)
    sys.exit(1)

for instance in instances:
    name = instance["name"]
    pixi_project_dir = instance["pixi_project_dir"]
    pixi_environment = instance["pixi_environment"]
    api_server_module = instance["api_server_module"]
    cmd_list = instance["cmd"]
    log_file = instance["log_file"]
    background = instance["background"]
    gpu_ids = instance.get("gpu_ids")

    inst_env = env.copy()
    inst_env["PYTHONUNBUFFERED"] = "1"

    if gpu_ids is not None and gpu_ids != "all":
        if gpu_ids == "none":
            inst_env["CUDA_VISIBLE_DEVICES"] = ""
        else:
            inst_env["CUDA_VISIBLE_DEVICES"] = str(gpu_ids)

    log_dir = os.path.dirname(log_file) or "."
    os.makedirs(log_dir, exist_ok=True)

    cmd = [
        pixi,
        "run",
        "--manifest-path",
        pixi_project_dir,
        "--environment",
        pixi_environment,
        "--frozen",
        "python",
        "-m",
        api_server_module,
        *map(str, cmd_list),
    ]

    print(f"[check-and-run-vllm] Launching {name}...")
    print(f"  Log: {log_file}")
    if gpu_ids is not None:
        print(f"  GPUs: {gpu_ids}")

    with open(log_file, "ab", buffering=0) as f:
        if background:
            proc = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, env=inst_env)
            print(f"  PID: {proc.pid}")
        else:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=inst_env, check=True)

print("[check-and-run-vllm] All instances processed.")
PY
