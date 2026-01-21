# How to Compile vLLM from Source with CUDA 12.6 for GLM-4.7

> **Note**: Official vLLM prebuilt wheels for recent versions (e.g., v0.14.0+) often target CUDA 12.1 or 12.8+. To use CUDA 12.6 (checking capabilities of GLM-4.7), you must compile from source.

## Prerequisites

- **NVIDIA CUDA Toolkit 12.6**: Ensure `nvcc --version` reports 12.6.
- **Python 3.9 - 3.12**: (3.12 is recommended for newer vLLM versions).
- **Build Tools**: `git`, `gcc`, `g++`, `ninja-build`.
- **Package Manager**: `uv` or `pixi` (highly recommended over raw pip).

## Methods

You can perform the compilation using either **System CUDA** (traditional) or **Pixi-managed CUDA** (isolated).

---

### Method A: Using System CUDA (Step-by-Step)

#### 1. Prepare Environment
```bash
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout v0.14.0  # Minimum for GLM-4.7

# Set environment to use /usr/local/cuda-12.6
export CUDA_HOME=/usr/local/cuda-12.6
export PATH=${CUDA_HOME}/bin:${PATH}
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
export MAX_JOBS=4  # Prevent OOM
```

#### 2. Compile with uv
```bash
uv venv .venv --python 3.12
source .venv/bin/activate

# Install PyTorch with CUDA 12.6 support (PyTorch 2.6+)
# Prefer native cu126 wheels if available to match your compiler
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126

# Fallback: If cu126 wheels aren't found, 2.5.1+cu124 enables the runtime, 
# but you MUST ensure you are compiling with the local CUDA 12.6 toolkit.
# uv pip install "torch==2.5.1+cu124" --index-url https://download.pytorch.org/whl/cu124

uv pip install -r requirements/build.txt
uv pip install --no-build-isolation -e .
```

---

### Method B: Using Pixi (Isolated Environment)

This method downloads the CUDA Toolkit 12.6 and compilers into a local folder, avoiding root modifications.

#### 1. Install/Update Pixi Configuration
If you don't have a project yet:
```bash
mkdir vllm-build && cd vllm-build
pixi init
```

#### 2. Add Dependencies
We use the `nvidia` channel for the official CUDA Toolkit and `conda-forge` for compilers.

```bash
# Add channels (priority: nvidia > conda-forge)
pixi project channel add nvidia conda-forge

# Install Toolkit + Compilers + Python
pixi add cuda-toolkit=12.6 gcc gxx ninja cmake git python=3.12
```

#### 3. Compile Inside Pixi Shell
Enter the shell where `nvcc` and `gcc` are verified to be the versions we just installed.

```bash
pixi shell
```

Inside the shell:

```bash
# Clone
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout v0.14.0

# Configure Environment for Pixi
export CUDA_HOME=$CONDA_PREFIX
# Optional: Force nvcc to use the pixi provided GCC
export CC=$CONDA_PREFIX/bin/gcc
export CXX=$CONDA_PREFIX/bin/g++

# Install PyTorch and Build Deps
# Using native cu126 wheels is ideal for alignment
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
uv pip install -r requirements/build.txt

# Compile
uv pip install --no-build-isolation -e .
```

---

## Running GLM-4.7

Once compiled (via either method), you can serve the model.

```bash
# Example command for GLM-4.7-Flash
vllm serve zai-org/GLM-4.7-Flash \
  --trust-remote-code \
  --tensor-parallel-size 1 \
  --tool-call-parser glm47 \
  --reasoning-parser glm45 \
  --enable-auto-tool-choice \
  --served-model-name glm-4.7
```

**Key Arguments:**
- `--tool-call-parser glm47`: Activation of the GLM-4.7 specific tool calling format.
- `--reasoning-parser glm45`: GLM-4.7 uses the reasoning parser definition from the previous iteration (glm45).

## References
- [vLLM Installation Guide](https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html)
- [GLM-4.7-Flash Model Card](https://huggingface.co/zai-org/GLM-4.7-Flash)
