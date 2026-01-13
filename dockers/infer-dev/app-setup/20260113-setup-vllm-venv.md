# Setup vLLM with venv (2026-01-13)

## Environment
- Container: `infer-dev:stage-2`
- User: `me`
- Workspace: `/hard/volume/workspace/vllm-project`
- CUDA: 12.6

## Steps

### 1. Prepare Workspace & Venv
Ensure `python` is available (via Pixi global or system). We will use the system python or pixi python to create the venv.

```bash
mkdir -p /hard/volume/workspace/vllm-project
cd /hard/volume/workspace/vllm-project
# Create venv
python3 -m venv .venv
# Activate
source .venv/bin/activate
```

### 2. Install Dependencies (CUDA 12.6)
Use the host proxy to speed up downloads.

```bash
export http_proxy=http://host.docker.internal:7890
export https_proxy=http://host.docker.internal:7890

# Upgrade pip
pip install --upgrade pip

# Install PyTorch for CUDA 12.6
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126

# Install vLLM
pip install vllm
```

### 3. Verification
```bash
python3 -c "import torch; print(f'Torch: {torch.__version__}, CUDA: {torch.version.cuda}'); import vllm; print(f'vLLM: {vllm.__version__}')"
```
