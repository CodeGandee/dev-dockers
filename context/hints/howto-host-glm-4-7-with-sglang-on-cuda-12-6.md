# How to Host GLM-4.7 with SGLang on CUDA 12.6 (8xA800)

This guide details how to host the **GLM-4.7** (and GLM-4.7-Flash) model using **SGLang** on an 8xA800 GPU cluster with **CUDA 12.6**. SGLang provides Day-0 support for GLM-4.7's advanced features like "Preserved Thinking" and "Interleaved Thinking".

## Prerequisites

-   **Hardware**: 8x NVIDIA A800 GPUs (80GB VRAM each).
-   **Driver/CUDA**: NVIDIA Driver compatible with CUDA 12.6.
-   **PyTorch**: **PyTorch 2.6.0** (Prebuilt for CUDA 12.6).
    -   *Command*: `pip install torch==2.6.0 torchvision --index-url https://download.pytorch.org/whl/cu126`
    -   *Note*: While newer versions (e.g., PyTorch 2.9.1) exist with CUDA 12.6 support, SGLang's custom kernels (`sgl-kernel`) are most stable with PyTorch 2.6.0 due to ABI compatibility.
-   **Python**: Python 3.10+.

## 1. Installation

GLM-4.7 support is very new. You likely need the latest development version of SGLang and Transformers.

### Option A: Install with uv (Standard)

SGLang's custom kernel (`sgl-kernel`) supports CUDA 12.1 and above (including 12.6). Using `uv` is recommended for faster and more reliable dependency resolution.

```bash
# 1. Install sgl-kernel (works for CUDA 12.1+)
uv pip install sglang

# 2. Install SGLang (Main Branch Recommended)
# As of Jan 2026, mainline releases should support it, but if 'glm47' parser is missing, install from source.
uv pip install "sglang[all]>=0.5.7" --find-links https://flashinfer.ai/whl/cu124/torch2.4/flashinfer/

# OR install from source if the latest pip version is outdated:
# git clone https://github.com/sgl-project/sglang.git
# cd sglang
# uv pip install -e "python[all]"
```

### Option B: Install with Pixi (Recommended for Reproducibility)

If you use **Pixi** for environment management, you can create a dedicated environment.

1.  **Initialize Project** (if starting fresh):
    ```bash
    pixi init sglang_project
    cd sglang_project
    ```

2.  **Add Python**:
    ```bash
    pixi add python=3.10
    ```

3.  **Add PyTorch and SGLang (via PyPI)**:
    Pixi handles PyPI packages seamlessly. Note the specific index URL for PyTorch and find-links for FlashInfer.

    ```bash
    # Install PyTorch 2.6.0 for CUDA 12.6
    pixi add --pypi torch==2.6.0 torchvision --index-url https://download.pytorch.org/whl/cu126

    # Install SGLang with FlashInfer kernels
    # Note: Use the flashinfer URL compatible with your installed torch version (often torch2.4 builds work for newer minor versions, or check flashinfer docs).
    pixi add --pypi "sglang[all]>=0.5.7" --find-links https://flashinfer.ai/whl/cu124/torch2.4/flashinfer/

    # Install ModelScope for downloading models
    pixi add --pypi modelscope
    ```

### Install Transformers

Ensure you have a recent version of `transformers` to support the model architecture.

```bash
# For uv
uv pip install -U transformers

# For Pixi
pixi add --pypi transformers --upgrade
```

## 2. Launching the Server

### Downloading Model from ModelScope (Alternative to Hugging Face)
If you prefer ModelScope or need a mirror in certain regions:

1.  **Install ModelScope**:
    ```bash
    uv pip install modelscope
    # OR
    pixi add --pypi modelscope
    ```
2.  **Download the Model**:
    ```bash
    modelscope download --model ZhipuAI/GLM-4.7 --local_dir ./weights/GLM-4.7
    ```

Use `python -m sglang.launch_server` (or `pixi run python ...`) to start the inference server.

### Key Configuration for GLM-4.7

-   **`--tool-call-parser glm47`**: **CRITICAL**. Enables the specific tool calling format for GLM-4.7.
-   **`--reasoning-parser glm45`**: **CRITICAL**. Enables "Preserved Thinking" and reasoning capabilities (often shared with GLM-4.5/Plus).
-   **`--tp 8`**: Sets Tensor Parallelism to 8 for your 8xA800 setup.
-   **`--trust-remote-code`**: Required for GLM models.

### Command Example (using ModelScope weights)

```bash
python3 -m sglang.launch_server \
  --model-path ./weights/GLM-4.7 \
  --served-model-name glm-4.7 \
  --tp-size 8 \
  --host 0.0.0.0 \
  --port 8000 \
  --trust-remote-code \
  --tool-call-parser glm47 \
  --reasoning-parser glm45 \
  --mem-fraction-static 0.9 \
  --disable-cuda-graph-padding
```

*Note: For `GLM-4.7-Flash`, replace `zai-org/GLM-4.7` with `zai-org/GLM-4.7-Flash`. You may also experiment with `--speculative-algorithm EAGLE` for the Flash model.*

## 3. Preserved Thinking Mode

GLM-4.7's "Preserved Thinking" allows the model to maintain a chain of thought across multi-turn agentic interactions.

-   **Server-side**: Enabled via `--reasoning-parser glm45`.
-   **Client-side**: When making requests (e.g., via OpenAI-compatible API), ensure your client handles the reasoning/thinking output correctly if it's interleaved.

## 4. Supported Model Variants

SGLang supports various quantization formats for GLM-4.7. Use these specific configurations for optimal performance.

### FP8 Variant (Recommended for H100/A800/Ada)
The official FP8 version provides a good balance of speed and memory usage on newer GPUs.

-   **Model**: `zai-org/GLM-4.7-FP8` (or `zai-org/GLM-4.7-Flash-FP8`)
-   **Key Flags**:
    -   `--kv-cache-dtype fp8_e5m2`: Reduces KV cache memory usage.
    -   `--quantization fp8`: Ensures correct loading of FP8 weights.
-   **Example Command**:
    ```bash
    python3 -m sglang.launch_server \
      --model-path zai-org/GLM-4.7-FP8 \
      --tp-size 8 \
      --tool-call-parser glm47 \
      --reasoning-parser glm45 \
      --quantization fp8 \
      --kv-cache-dtype fp8_e5m2 \
      --trust-remote-code \
      --port 8000
    ```

### AWQ Variant (INT4)
Community quantized versions (e.g., by `cyankiwi` or `QuantTrio`) are available for lower VRAM usage.

-   **Model**: `cyankiwi/GLM-4.7-Flash-AWQ-4bit` (example)
-   **Key Flags**:
    -   `--quantization awq` (or `--quantization awq_marlin` for faster inference on compatible GPUs).
-   **Example Command**:
    ```bash
    python3 -m sglang.launch_server \
      --model-path cyankiwi/GLM-4.7-Flash-AWQ-4bit \
      --tp-size 4 \
      --tool-call-parser glm47 \
      --reasoning-parser glm45 \
      --quantization awq_marlin \
      --trust-remote-code
    ```

## 5. Troubleshooting

### "Invalid choice: 'glm47'" Error
If you see `argument --tool-call-parser: invalid choice: 'glm47'`, your SGLang version is too old.
**Solution**: Uninstall `sglang` and reinstall from the main branch source or a newer dev wheel.

### "Watch Dog TimeOut" on A800
Some users report watchdog timeouts on 8xA800 setups with large models.
**Solution**:
-   Increase `--watchdog-timeout` (default is usually small, try `600` or more).
-   Ensure `--nccl-init-addr` is set correctly if using multiple nodes (not needed for single node 8xGPU).

### CUDA Version Mismatch
If `sgl-kernel` fails to load:
-   Verify `nvcc --version` matches (or is compatible with) the `sgl-kernel` build.
-   CUDA 12.6 is generally backward compatible with 12.x kernels, but ensure your PyTorch version (e.g., 2.4/2.5) matches the CUDA version used to build SGLang components.
