# `sglang-infer` (Pixi) — GLM-4.7 inference with SGLang (cu126 + cu128, multi‑GPU)

This sub-project is a **Pixi-managed** environment for running **SGLang** to serve **GLM-4.7** with **tensor parallel (multi‑GPU)**.

Reference: `context/hints/howto-host-glm-4-7-with-sglang-on-cuda-12-6.md`.

## Requirements

- NVIDIA driver + GPUs available on the host
- No host CUDA toolkit/runtime required: this Pixi project installs CUDA runtime libraries via **conda-forge**.
  - You still need the NVIDIA **driver** (it provides `libcuda.so`).
- Pixi installed on the machine where you’ll create/use the env

## Environments (CUDA compatibility)

This project defines **two Pixi environments**:

- `default` (**cu126 / CUDA 12.6**) — for hosts whose NVIDIA driver supports CUDA 12.6.
  - Uses: `sglang==0.5.7` (PyPI) + `torch==2.9.1+cu126` / `torchvision==0.24.1+cu126` / `torchaudio==2.9.1+cu126` (PyTorch CUDA index)
- `cu128` (**cu128 / CUDA 12.8**) — for newer drivers (and current GLM‑4.7 workflows).
  - Uses: `sglang==0.5.7` (PyPI) + `torch==2.9.1+cu128` / `torchvision==0.24.1+cu128` / `torchaudio==2.9.1+cu128` (PyTorch CUDA index)

## 1) Enter the project directory

From repo root:

```bash
cd dockers/infer-dev/sub-projects/sglang-infer
```

## 1.0) Package cache location (required)

To support “prepare online, run offline” workflows, this project stores **all downloaded packages** under:

- `dockers/infer-dev/sub-projects/sglang-infer/.pkg-cache/`

Create cache dirs and export cache env vars (run in every shell before `pixi add/install/run`):

```bash
export SGLANG_INFER_DIR="$(pwd)"
export PKG_CACHE_DIR="${SGLANG_INFER_DIR}/.pkg-cache"

mkdir -p \
  "${PKG_CACHE_DIR}/conda/rattler" \
  "${PKG_CACHE_DIR}/pypi/uv" \
  "${PKG_CACHE_DIR}/pypi/pip" \
  "${PKG_CACHE_DIR}/pixi" \
  "${PKG_CACHE_DIR}/xdg"

# Conda/conda-forge downloads (Pixi uses Rattler internally)
export RATTLER_CACHE_DIR="${PKG_CACHE_DIR}/conda/rattler"

# PyPI downloads (Pixi uses uv internally)
export UV_CACHE_DIR="${PKG_CACHE_DIR}/pypi/uv"

# If you run `pip` manually, keep its cache in-repo too (Pixi itself uses `uv`)
export PIP_CACHE_DIR="${PKG_CACHE_DIR}/pypi/pip"

# Pixi internal cache (best-effort; keep inside repo for reproducibility)
export PIXI_CACHE_DIR="${PKG_CACHE_DIR}/pixi"

# Catch-all cache root for other tools used by Pixi
export XDG_CACHE_HOME="${PKG_CACHE_DIR}/xdg"
```

Notes:
- Downloads/metadata should land under `.pkg-cache/`.
- The actual installed environment prefix is still under `.pixi/envs/...` (that’s expected).

One-liner (no exports) for `pixi install`:

```bash
RATTLER_CACHE_DIR="$PWD/.pkg-cache/conda/rattler" \
UV_CACHE_DIR="$PWD/.pkg-cache/pypi/uv" \
PIP_CACHE_DIR="$PWD/.pkg-cache/pypi/pip" \
PIXI_CACHE_DIR="$PWD/.pkg-cache/pixi" \
XDG_CACHE_HOME="$PWD/.pkg-cache/xdg" \
pixi install
```

## 2) Install the environments

Install **cu126** (default environment):

```bash
pixi install
```

Install **cu128**:

```bash
pixi install --environment cu128
```

## 3) Sanity check (CUDA + versions)

cu126 / default:

```bash
pixi run python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available(), 'device_count', torch.cuda.device_count() if torch.cuda.is_available() else 0)"
pixi run python -c "import sglang; print('sglang', getattr(sglang, '__version__', 'unknown'))"
```

cu128:

```bash
pixi run --environment cu128 python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available(), 'device_count', torch.cuda.device_count() if torch.cuda.is_available() else 0)"
pixi run --environment cu128 python -c "import sglang; print('sglang', getattr(sglang, '__version__', 'unknown'))"
```

## 4) Prepare GLM-4.7 model weights

You need a local directory containing the model weights (for offline usage, download on an online machine first).

Example using ModelScope:

```bash
pixi run modelscope download --model ZhipuAI/GLM-4.7 --local_dir ./weights/GLM-4.7
```

After download, expect something like:

```text
./weights/GLM-4.7/
  config.json
  tokenizer.json
  model.safetensors (or shards)
  ...
```

## 5) Launch SGLang server (multi‑GPU / tensor parallel)

Key flags for GLM-4.7 (see the reference hint):

- `--tool-call-parser glm47` (**required** for GLM‑4.7 tool format)
- `--reasoning-parser glm45` (**required** for preserved/interleaved thinking)
- `--tp-size <N>` tensor parallel size (must match the number of visible GPUs)
- `--trust-remote-code` (required for GLM models)

Example: 8 GPUs (single node)

```bash
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7

pixi run --environment cu128 python -m sglang.launch_server \
  --model-path ./weights/GLM-4.7 \
  --served-model-name glm-4.7 \
  --tp-size 8 \
  --host 0.0.0.0 \
  --port 30000 \
  --trust-remote-code \
  --tool-call-parser glm47 \
  --reasoning-parser glm45 \
  --mem-fraction-static 0.9 \
  --disable-cuda-graph-padding
```

## 6) Test that serving works (must return a valid response)

In a separate shell:

```bash
curl -fsS http://127.0.0.1:30000/v1/models
```

Then a real inference request:

```bash
curl -fsS http://127.0.0.1:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role":"user","content":"Say hi in one short sentence."}],
    "max_tokens": 64
  }'
```

## Smoke test: `models/qwen2-vl-7b` (cu126 then cu128)

This repo includes a simple start → query → stop smoke test script for Qwen2-VL-7B:

```bash
bash dockers/infer-dev/sub-projects/sglang-infer/scripts/smoke-qwen2-vl-7b-cu126-then-cu128.sh
```

Useful overrides:

- `SGLANG_MODEL_DIR=/abs/path/to/model`
- `SGLANG_TP_SIZE_CU126=1` / `SGLANG_TP_SIZE_CU128=1`
- `SGLANG_RUN_MODE=cu126|cu128|both`

## Troubleshooting quick notes

- `invalid choice: 'glm47'` → upgrade SGLang (too old).
- `sgl-kernel` / ABI issues → ensure torch/torchvision/torchaudio are pinned to matching PyTorch CUDA-local versions (e.g. `2.9.1+cu126` / `0.24.1+cu126`).
- Multi‑GPU issues / timeouts → try increasing watchdog timeout (if supported by your SGLang version) and verify NCCL is healthy.
