# Contract: Llama.cpp TOML Configuration

## Purpose

Defines the structure and behavior of the `.toml` configuration file used by the `check-and-run-llama-cpp.sh` script to launch `llama-server`.

## Schema

See `context/design/contract/llama-cpp-config-toml.schema.json` for a JSON Schema representation of this TOML contract (useful for validation and tooling).

## File Location

The path to this file is specified by the environment variable `AUTO_INFER_LLAMA_CPP_CONFIG`.
Example: `/app/config/llama_config.toml`

**Important**: All paths specified in this configuration file (including `model`, `log_dir`, `log_file`, `llama_cpp_path`) must be valid paths **inside the container**.

## Structure

The TOML file uses a hierarchical structure where global defaults can be defined and then overridden or extended by specific model instances.

### 1. Master Configuration `[master]`
- **Keys**:
  - `enable` (Optional, bool): Global switch to enable/disable the entire auto-launch process. Default: `true`.
  - `llama_cpp_path` (Optional, string): Path to the `llama-server` executable **inside the container**. Default: `llama-server` (assumed to be in PATH).

### 2. Global Defaults

#### a. `[instance.control]` (Global Launcher Defaults)
- Defines default behavior for the launcher script across all instances.
- **Keys**:
  - `log_dir` (Optional, string): Base directory for logs **inside the container**. Default: `/tmp`.
  - `background` (Optional, bool): Default background setting. Default: `true`.

#### b. `[instance.server]` (Global Server Defaults)
- Defines common `llama-server` arguments shared by all instances (e.g., hardware config, host binding).
- **Keys**: Same as the server argument rules (see below).

### 3. Model Instances `[instance.<model-name>]`

Each key in `[instance]` that is **not** `control` or `server` is treated as a specific model configuration.

#### a. `[instance.<model-name>.control]` (Instance Launcher Settings)
- Overrides settings from `[instance.control]`.
- **Keys**:
  - `log_file` (Optional, string): Specific log file path **inside the container**. If set, ignores `log_dir`.
  - `background` (Optional, bool): Overrides global background setting.
  - `enabled` (Optional, bool): Whether to launch this specific instance. Default: `true`.
  - `gpu_ids` (Optional, string): String specifying GPU visibility.
      - **"all"** (or omitted): Use system default (usually all visible GPUs).
      - **"none"**: Use no GPUs (CPU only, sets `CUDA_VISIBLE_DEVICES=""`).
      - **"0,1,..."**: Comma-separated list of specific GPU IDs (sets `CUDA_VISIBLE_DEVICES="0,1..."`).

#### b. `[instance.<model-name>.server]` (Instance Server Arguments)
- Overrides or merges with `[instance.server]`.
- **Merge Logic**:
  - Scalar values (string/int/bool) in the specific instance **replace** values from the global default.
  - Lists (e.g., `lora`, `extra_args`) are **concatenated** (Global + Instance).

### Server Argument Rules (for `server` sections)

1.  **Key Name Mapping**:
    - Underscores (`_`) in keys are converted to hyphens (`-`).
    - Keys are prefixed with `--` to form the argument flag.
    - *Exception*: Specific keys might have short aliases (e.g., `model` -> `-m`), but using the full name (e.g., `model` -> `--model`) is preferred for consistency. The script will use the long form by default.

2.  **Value Handling**:
    - **String/Number**: Converted to `--key value`.
        - Special Note for `model`: This path must be a valid path **inside the container**. It can point to:
            1.  A single `.gguf` file.
            2.  A sharded GGUF model: point to the *first* shard file (e.g., `...-00001-of-00003.gguf`) so `llama-server` can load the full set.
    - **Boolean**: Use only for “valueless” flags. `true` adds `--flag`; `false` is ignored.
        - If a flag requires a value (e.g., `flash_attn`), provide a string value instead.
    - **List/Array**: Repeated arguments (e.g., `--lora`).
    - **reserved key**: `extra_args` (List of raw strings).

## Example Configuration

```toml
[master]
enable = true
llama_cpp_path = "/usr/local/bin/llama-server"

[instance.control]
log_dir = "/var/log/llama"
background = true
# Default: Use all GPUs (omitted)

[instance.server]
# Common defaults for all models
host = "0.0.0.0"
n_gpu_layers = 99
metrics = true
# llama-server expects an explicit value: on|off|auto
flash_attn = "auto"

# Instance 1: Llama 3 (Single File)
[instance.llama-3-8b]
    [instance.llama-3-8b.server]
    model = "/path/to/models/llama-3-8b.gguf"
    port = 8080
    alias = "llama3"
    ctx_size = 8192

# Instance 2: GLM-4 (Sharded GGUF)
[instance.glm-4]
    [instance.glm-4.server]
    # Points to the first shard; remaining shards are loaded automatically
    model = "/path/to/models/GLM-4.7-Q2_K-00001-of-00003.gguf"
    port = 8081
    alias = "glm4"
```

## Parsing Logic (Python Snippet)

The python inline script will:
1. Load the TOML.
2. Check `master.enable`. If false, exit/return empty list.
3. Extract `llama_cpp_path` from `master`.
4. Extract `global_control` from `instance.get('control', {})`.
5. Extract `global_server` from `instance.get('server', {})`.
6. Iterate through keys in `instance`:
    - Skip if key is `control` or `server`.
    - `model_name` = key.
    - `model_config` = value.
7. For each model:
    - **Control Merge**: `final_control` = `global_control.copy().update(model_config.get('control', {}))`.
    - **Server Merge**:
        - Start with `final_server` = `global_server.copy()`.
        - Update with `model_config.get('server', {})` (handling list concatenation vs scalar overwrite).
    - **Output**: JSON object with `name`, `final_control` (containing `gpu_ids` as string or None), `final_server` args list, and global `llama_cpp_path`.

## Validation

The script will minimally validate that `model` is present or provided via `extra_args` (though `llama-server` might complain if missing).
