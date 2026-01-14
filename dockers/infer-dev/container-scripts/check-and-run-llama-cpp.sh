#!/usr/bin/env bash

# check-and-run-llama-cpp.sh
# Checks for AUTO_INFER_LLAMA_CPP_CONFIG environment variable and launches llama-server instances.

set -euo pipefail

CONFIG_VAR="AUTO_INFER_LLAMA_CPP_CONFIG"
CONFIG_FILE="${!CONFIG_VAR:-}"

if [[ -z "$CONFIG_FILE" ]]; then
    # echo "[check-and-run-llama-cpp] $CONFIG_VAR not set. Skipping auto-launch."
    exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[check-and-run-llama-cpp] Config file not found at: $CONFIG_FILE. Skipping."
    exit 0
fi

echo "[check-and-run-llama-cpp] Found config at $CONFIG_FILE. Parsing..."

# Inline Python script to parse TOML and output JSON
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

def parse_toml(file_path):
    with open(file_path, "rb") as f:
        data = tomllib.load(f)
    
    # 0. Check Master Config
    master_config = data.get("master", {})
    if not master_config.get("enable", True):
        # Return empty list to signal no action
        print(json.dumps([]))
        return

    llama_executable = master_config.get("llama_cpp_path", "llama-server")

    # Root 'instance' table
    instances_data = data.get("instance", {})
    
    # 1. Extract Global Defaults
    global_control = instances_data.get("control", {})
    global_server = instances_data.get("server", {})
    
    results = []

    # 2. Iterate over actual model instances
    for key, value in instances_data.items():
        if key in ("control", "server"):
            continue # specific reserved keys
        
        if not isinstance(value, dict):
            continue

        model_name = key
        model_config = value
        
        # Merge Control
        # Defaults: enabled=True
        # Logic: global.copy() -> update(model)
        final_control = global_control.copy()
        final_control.update(model_config.get("control", {}))
        
        # Check enabled
        if not final_control.get("enabled", True):
            continue

        # Merge Server Args
        # Logic: global.copy() -> update(model), but concatenate lists
        final_server = global_server.copy()
        model_server = model_config.get("server", {})
        
        for k, v in model_server.items():
            if k in final_server and isinstance(final_server[k], list) and isinstance(v, list):
                final_server[k] = final_server[k] + v
            else:
                final_server[k] = v
                
        # Build Command List
        cmd_args = []
        
        # Helper to format keys
        def format_key(k):
            # alias handling can happen here or assume user provides correct flags
            # simplistic approach: replace _ with - and prepend --
            # Special case: 'model' -> usually -m, but --model works too
            return "--" + k.replace("_", "-")

        # Process 'extra_args' first (or last, doesn't matter much)
        extra = final_server.pop("extra_args", [])
        if isinstance(extra, list):
            cmd_args.extend(map(str, extra))
            
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
                
        # Determine Log File
        log_dir = final_control.get("log_dir", "/tmp")
        default_log = os.path.join(log_dir, f"llama-server-{model_name}.log")
        log_file = final_control.get("log_file", default_log)
        
        # Determine Background
        background = final_control.get("background", True)

        # Determine GPU IDs (string or None)
        gpu_ids = final_control.get("gpu_ids")

        results.append({
            "name": model_name,
            "executable": llama_executable,
            "cmd": cmd_args,
            "log_file": log_file,
            "background": background,
            "gpu_ids": gpu_ids
        })
        
    print(json.dumps(results))

if __name__ == "__main__":
    parse_toml(sys.argv[1])
EOF
)

# Execute Python parser
PARSED_JSON=$(python3 -c "$PYTHON_PARSER" "$CONFIG_FILE")

# Iterate over the results
# Using jq is safer, but avoiding extra dependency if python is available is nice.
# Since we have python, let's use a small python loop to execute commands or print shell commands
# to be eval'd. Printing shell commands to eval is robust.

LAUNCH_SCRIPT=$(python3 -c "
import sys, json, shlex

data = json.loads(sys.argv[1])
for instance in data:
    name = instance['name']
    executable = instance['executable']
    cmd_list = instance['cmd']
    log_file = instance['log_file']
    bg = instance['background']
    gpu_ids = instance.get('gpu_ids') # String or None
    
    # Construct env vars
    env_prefix = ''
    
    if gpu_ids is not None and gpu_ids != 'all':
        if gpu_ids == 'none':
            # "none" -> No GPUs
            env_prefix = 'CUDA_VISIBLE_DEVICES=\"\" '
        else:
            # Specific IDs string (e.g., "0,1")
            env_prefix = f'CUDA_VISIBLE_DEVICES={shlex.quote(str(gpu_ids))} '

    # Construct command string safe for shell
    cmd_str = env_prefix + shlex.quote(executable) + ' ' + ' '.join(shlex.quote(x) for x in cmd_list)
    
    print(f'echo \"[check-and-run-llama-cpp] Launching {name}...\"')
    print(f'echo \"  Log: {log_file}\"')
    if gpu_ids is not None:
        print(f'echo \"  GPUs: {gpu_ids}\"')
    
    # Ensure log dir exists
    print(f'mkdir -p \"$(dirname {shlex.quote(log_file)})\"')
    
    full_cmd = f'{cmd_str} > {shlex.quote(log_file)} 2>&1'
    
    if bg:
        full_cmd += ' &'
        
    print(full_cmd)
    
    if bg:
        # print PID capture if needed, but simple echo is fine for now
        print(f'echo \"  PID: $!\"')
" "$PARSED_JSON")

eval "$LAUNCH_SCRIPT"

echo "[check-and-run-llama-cpp] All instances processed."
