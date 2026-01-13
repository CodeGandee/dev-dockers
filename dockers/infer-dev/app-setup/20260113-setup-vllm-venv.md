# Setup vLLM with venv (2026-01-13)

## Environment
- Container: `infer-dev:stage-2`
- User: `me`
- Workspace: `/hard/volume/workspace/vllm-project`
- CUDA: 12.6

## Steps

### 1. Prepare Workspace & Venv
Ensure `python` and development headers are available. `python3-dev` is required for vLLM (triton/torch.compile) to build custom kernels.

```bash
# As root:
# apt update && apt install -y python3-venv python3-dev

mkdir -p /hard/volume/workspace/vllm-project


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

### 4. Launching for Inference (vLLM)

To run vLLM with specific GPUs (e.g., GPUs 0-3) and an OpenAI-compatible server:

```bash
# Activate venv
source .venv/bin/activate

# Set GPU visibility
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Start API Server
python3 -m vllm.entrypoints.openai.api_server \
  --model /hard/volume/data/llm-models/Llama-2-7b-hf \
  --tensor-parallel-size 4 \
  --host 0.0.0.0 \
  --port 8000
```

**Key Parameters:**
- `CUDA_VISIBLE_DEVICES=0,1,2,3`: Restricts vLLM to the first 4 GPUs.
- `--tensor-parallel-size 4`: Distributes the model across the 4 visible GPUs.
- `--model <path>`: Path to the Hugging Face format model directory.
