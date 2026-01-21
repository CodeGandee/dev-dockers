# vLLM Environment Requirements (GPU)

This guide outlines the environment requirements for running the latest version of **vLLM** with NVIDIA GPU support, based on the documented standards as of early 2026.

## Quick Summary

| Component | Recommendation | Notes |
| :--- | :--- | :--- |
| **Python** | **3.12** | Highly recommended; required for some hardware backends. |
| **CUDA** | **12.9** (Default) | Pre-built binaries available for **12.8**, **12.9**, **13.0**. |
| **PyTorch** | Auto-detected | Bundled/Compatible version installed automatically. |
| **GPU** | Compute Cap 7.0+ | **Blackwell (B200/GB200)** requires CUDA 12.8+. |

## Detailed Requirements

### 1. CUDA Version
The latest vLLM pre-built binaries are compiled with modern CUDA versions to support recent hardware features.
- **Default:** CUDA 12.9
- **Supported:** CUDA 12.8, 13.0 (available via specific indices)
- **Legacy:** Older CUDA versions (e.g., 11.8) may require building from source or using older vLLM releases.

#### CUDA 12.6 Specific Compatibility
- **Standard PyPI:** Pre-built wheels supported up to **v0.8.5**.
- **GitHub Artifacts:** Supported up to **v0.9.0** (requires manual wheel download from GitHub Releases).
- **Newer Versions (v0.10+):** Generally require CUDA 12.8+ or building from source.
  - See [How to Compile vLLM from Source with CUDA 12.6](./howto-compile-vllm-cuda-12-6-for-glm-4-7.md) for detailed instructions on building newer versions (like v0.14.0 for GLM-4.7) on CUDA 12.6.

### 2. Python Version
- **Version 3.12** is standard for the latest releases.
- Ensure your environment is isolated (using `uv`, `conda`, or `venv`) to avoid conflicts, as vLLM is sensitive to PyTorch/CUDA version mismatches.

### 3. Installation Methods

#### Using `uv` (Recommended)
`uv` can automatically select the appropriate PyTorch backend.

```bash
# Create environment
uv venv --python 3.12
source .venv/bin/activate

# Install with auto-detection for CUDA
uv pip install vllm --torch-backend=auto
```

#### Installing Specific CUDA Versions
To target a specific CUDA version (e.g., CUDA 13.0):

```bash
export VLLM_VERSION=$(curl -s https://api.github.com/repos/vllm-project/vllm/releases/latest | jq -r .tag_name | sed 's/^v//')
export CUDA_VERSION=130
export CPU_ARCH=$(uname -m)

uv pip install https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}+cu${CUDA_VERSION}-cp312-abi3-manylinux_2_35_${CPU_ARCH}.whl \
    --extra-index-url https://download.pytorch.org/whl/cu${CUDA_VERSION}
```

### 4. Verification
After installation, verify the setup and CUDA version detection:

```bash
python -c "import torch, vllm; print(f'PyTorch: {torch.__version__}, CUDA: {torch.version.cuda}, vLLM: {vllm.__version__}')"
```

## References
- [vLLM Installation Documentation](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/)
- [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit)
