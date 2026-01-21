# Model Configuration Guide

This directory contains TOML configuration files used by the `infer-dev` container to automatically launch:
- `llama-server` (llama.cpp, OpenAI-compatible)
- `vllm.entrypoints.openai.api_server` (vLLM, OpenAI-compatible)

The configuration format allows defining global defaults and specific model instances, including hardware control (GPU visibility) and server arguments.

## File Structure

The configuration is hierarchical:

1.  **[master]**: Global settings for the launcher.
2.  **[instance.control]** & **[instance.server]**: Global defaults for all instances.
3.  **[instance.<name>]**: Specific settings for a model instance, overriding defaults.

### 1. Master Configuration
```toml
[master]
enable = true
# Optional: path to llama-server binary inside container.
# If omitted, auto-detects in:
# 1. /soft/app/llama-cpp/bin/llama-server (installed pkg)
# 2. /hard/volume/workspace/llama-cpp/build/bin/llama-server (local build)
# 3. PATH
llama_cpp_path = "..."
```

### 2. Global Defaults
```toml
# Default launcher behavior
[instance.control]
log_dir = "/tmp"  # Where logs go
background = true # Run in background

# Default server arguments (applied to all models)
[instance.server]
host = "0.0.0.0"
n_gpu_layers = -1 # Offload all layers to GPU
flash_attn = "on" # Enable Flash Attention
```

### 3. Model Instances
Define one or more instances. Each instance runs as a separate process.

```toml
[instance.my-model]
    # Control settings for this instance
    [instance.my-model.control]
    # GPU Isolation:
    # "all" (default), "none" (CPU only), or "0,1,2,3" (specific IDs)
    gpu_ids = "0,1,2,3"
    log_file = "/tmp/my-model.log"

    # Server arguments for this instance
    [instance.my-model.server]
    # Path inside container (use the mount point!)
    model = "/llm-models/MyModel/model.gguf"
    # For sharded models, point to the first shard:
    # model = "/llm-models/GLM-4/glm-4-00001-of-00003.gguf"
    
    port = 8080
    alias = "my-model"
    ctx_size = 8192
    
    # Jinja template support (recommended for newer models like GLM-4)
    jinja = true
    # Note: Avoid hardcoding 'chat_template' if using 'jinja=true', 
    # let the server detect it from the GGUF metadata.
```

## Key Options

| Section | Key | Description |
| :--- | :--- | :--- |
| `instance.*.control` | `gpu_ids` | Comma-separated list of GPU IDs to use (e.g., `"0,1"`). |
| `instance.*.server` | `model` | Path to the GGUF file inside the container. |
| `instance.*.server` | `port` | HTTP port to listen on. |
| `instance.*.server` | `jinja` | Set to `true` to use Jinja2 templating (often required for accurate chat templates). |
| `instance.*.server` | `ctx_size` | Context window size. |
| `instance.*.server` | `n_gpu_layers` | Number of layers to offload to GPU (`-1` for all). |

## Usage

1.  Create a `.toml` file in this directory (e.g., `my-model.toml`).
2.  Set the environment variable `AUTO_INFER_LLAMA_CPP_CONFIG` to the path of this file inside the container (e.g., `/model-configs/my-model.toml`).
3.  Set `AUTO_INFER_LLAMA_CPP_ON_BOOT=1`.

### vLLM usage (Pixi-backed)

1.  Create a vLLM `.toml` file in this directory (e.g., `vllm-qwen2-vl-7b.toml`).
2.  Set `AUTO_INFER_VLLM_CONFIG=/model-configs/vllm-qwen2-vl-7b.toml`.
3.  Set `AUTO_INFER_VLLM_ON_BOOT=1`.
4.  If you are using a Pixi-Pack offline bundle, also set:
    - `AUTO_INFER_VLLM_BUNDLE_ON_BOOT=1`
    - `AUTO_INFER_VLLM_BUNDLE_PATH=/hard/volume/workspace/<bundle>.tar`

See:
- `context/design/contract/def-llama-cpp-config-toml.md` (llama.cpp runner)
- `context/design/contract/def-vllm-config-toml.md` (vLLM runner)
