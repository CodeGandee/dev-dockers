# Contract: SGLang TOML Configuration

## Purpose

Defines the structure and behavior of the `.toml` configuration file used by `dockers/infer-dev/installation/stage-2/custom/check-and-run-sglang.sh` to launch one or more SGLang OpenAI-compatible servers (`python -m sglang.launch_server`).

## File Location

The path to this file is specified by the environment variable `AUTO_INFER_SGLANG_CONFIG`.

**Important**: All paths specified in this configuration file (including `model_path`, `log_dir`, `log_file`, `project_dir`, `python_path`) must be valid paths **inside the container**.

## Overrides

If `AUTO_INFER_SGLANG_OVERRIDES` is set (JSON string), it is deep-merged into the parsed TOML before launching. This is intended for quick per-run tweaks without editing the TOML file.

## Structure

The TOML file uses the same “global defaults + per-instance overrides” pattern as the llama.cpp and vLLM runners.

### 1. Master Configuration `[master]`

- `enable` (Optional, bool): Global switch to enable/disable the entire auto-launch process. Default: `true`.
- `project_dir` (Optional, string): Base directory for the SGLang runtime environment. Default: `/hard/volume/workspace/sglang-pixi-offline`.
  - In the Pixi-pack workflow, this dir contains:
    - `env/` (unpacked conda environment)
    - `activate.sh`
    - `.installed-from.json` marker
- `python_path` (Optional, string): Python interpreter path used to run the server module. Default: `<project_dir>/env/bin/python`.
- `server_module` (Optional, string): Python module run with `-m`. Default: `sglang.launch_server`.

### 2. Global Defaults

#### a. `[instance.control]` (Global Launcher Defaults)

- `log_dir` (Optional, string): Base directory for logs **inside the container**. Default: `/tmp`.
- `background` (Optional, bool): Run in background by default. Default: `true`.

#### b. `[instance.server]` (Global SGLang Server Defaults)

Defines common `sglang.launch_server` arguments shared by all instances (e.g. `host`, `port`, `tp_size`, `trust_remote_code`, `tool_call_parser`, `reasoning_parser`).

### 3. Model Instances `[instance.<name>]`

Each key in `[instance]` that is **not** `control` or `server` is treated as a separate SGLang server instance.

#### a. `[instance.<name>.control]` (Instance Launcher Settings)

- `enabled` (Optional, bool): Whether to launch this instance. Default: `true`.
- `background` (Optional, bool): Overrides global background setting.
- `log_file` (Optional, string): Specific log file path **inside the container**. If set, overrides `log_dir`.
- `gpu_ids` (Optional, string): String specifying GPU visibility:
  - `"all"` (or omitted): Use system default.
  - `"none"`: Use no GPUs (CPU only, sets `CUDA_VISIBLE_DEVICES=""`).
  - `"0,1,..."`: Comma-separated list of GPU IDs (sets `CUDA_VISIBLE_DEVICES="0,1..."`).

#### b. `[instance.<name>.server]` (Instance SGLang Arguments)

This section is converted into CLI flags for `python -m sglang.launch_server`:

- Underscores (`_`) become hyphens (`-`) and keys are prefixed with `--`.
  - Example: `model_path` -> `--model-path`
  - Example: `served_model_name` -> `--served-model-name`
  - Example: `tp_size` -> `--tp-size`
- Values:
  - String/Number: `--key value`
  - Boolean: if `true`, add `--flag` (valueless flags like `--trust-remote-code`); if `false`, omit
  - List: repeated `--key value` pairs
  - Reserved key: `extra_args` (List of raw CLI tokens appended as-is)

Notes:
- If you prefer SGLang’s YAML config mode, you can use `extra_args = ["--config", "/path/to/config.yaml"]` and omit individual keys.

## Example Configuration

See `dockers/infer-dev/model-configs/sglang-*.toml`.

