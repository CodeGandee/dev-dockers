# Contract: vLLM TOML Configuration

## Purpose

Defines the structure and behavior of the `.toml` configuration file used by `dockers/infer-dev/installation/stage-2/custom/check-and-run-vllm.sh` to launch one or more vLLM OpenAI-compatible API servers.

## File Location

The path to this file is specified by the environment variable `AUTO_INFER_VLLM_CONFIG`.

**Important**: All paths specified in this configuration file (including `model`, `log_dir`, `log_file`, `pixi_project_dir`) must be valid paths **inside the container**.

## Overrides

If `AUTO_INFER_VLLM_OVERRIDES` is set (JSON string), it is deep-merged into the parsed TOML before launching. This is intended for quick per-run tweaks without editing the TOML file.

## Structure

The TOML file uses the same “global defaults + per-instance overrides” pattern as the llama.cpp runner.

### 1. Master Configuration `[master]`

- `enable` (Optional, bool): Global switch to enable/disable the entire auto-launch process. Default: `true`.
- `pixi_project_dir` (Optional, string): Path to a Pixi project directory **inside the container** used to launch vLLM via `pixi run --manifest-path <dir> ...`.
  - This directory should contain `pixi.toml`, `pixi.lock`, and an installed Pixi environment (typically `.pixi/envs/default`).
- `pixi_environment` (Optional, string): Pixi environment name to use. Default: `default`.
- `api_server_module` (Optional, string): Python module to run. Default: `vllm.entrypoints.openai.api_server`.

Notes:
- In the Pixi Pack offline workflow, the project dir is initialized by extracting an offline bundle tar (contains `channel/`) and then running `pixi install --frozen` with channels set to `["./channel"]`.

### 2. Global Defaults

#### a. `[instance.control]` (Global Launcher Defaults)

- `log_dir` (Optional, string): Base directory for logs **inside the container**. Default: `/tmp`.
- `background` (Optional, bool): Run in background by default. Default: `true`.

#### b. `[instance.server]` (Global vLLM Server Defaults)

Defines common vLLM API server arguments shared by all instances (e.g. `host`, `gpu_memory_utilization`, `max_model_len`, `trust_remote_code`).

### 3. Model Instances `[instance.<name>]`

Each key in `[instance]` that is **not** `control` or `server` is treated as a separate vLLM server instance.

#### a. `[instance.<name>.control]` (Instance Launcher Settings)

- `enabled` (Optional, bool): Whether to launch this instance. Default: `true`.
- `background` (Optional, bool): Overrides global background setting.
- `log_file` (Optional, string): Specific log file path **inside the container**. If set, overrides `log_dir`.
- `gpu_ids` (Optional, string): String specifying GPU visibility:
  - `"all"` (or omitted): Use system default.
  - `"none"`: Use no GPUs (CPU only, sets `CUDA_VISIBLE_DEVICES=""`).
  - `"0,1,..."`: Comma-separated list of GPU IDs (sets `CUDA_VISIBLE_DEVICES="0,1..."`).

#### b. `[instance.<name>.server]` (Instance vLLM Arguments)

This section is converted into CLI flags for `python -m vllm.entrypoints.openai.api_server`:

- Underscores (`_`) become hyphens (`-`) and keys are prefixed with `--`.
  - Example: `served_model_name` -> `--served-model-name`
  - Example: `max_model_len` -> `--max-model-len`
- Values:
  - String/Number: `--key value`
  - Boolean: if `true`, add `--flag` (valueless flags like `--trust-remote-code`); if `false`, omit
  - List: repeated `--key value` pairs
  - Reserved key: `extra_args` (List of raw CLI tokens appended as-is)

### Notes on vLLM flags

- `model` must be a HuggingFace-style model directory path that is visible inside the container (mounted path is typical).
- For Qwen2-VL and other multi-modal models, `trust_remote_code=true` is commonly required and `enable_mm_embeds=true` may be needed depending on model/runtime.

## Example Configuration

See the vLLM config examples under `dockers/infer-dev/model-configs/` (to be added when implementing the runner).
