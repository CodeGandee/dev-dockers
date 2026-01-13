# Setup llama.cpp (2026-01-13)

## Environment
- Container: `infer-dev:stage-2`
- User: `me` (with `root` access for installation)
- Workspace: `/hard/volume/workspace/llama-cpp` (mapped from host `dockers/infer-dev/.container/workspace/llama-cpp`)

## Steps

### 1. Install Build Tools
Install system-level dependencies for building C++ projects and CUDA support.

```bash
# As root:
# apt update && apt install -y cmake ninja-build libcurl4-openssl-dev
```

### 2. Configure Build (CUDA)
Configure with CUDA enabled and use Ninja for faster builds.

```bash
cd /hard/volume/workspace/llama-cpp
cmake -B build -DGGML_CUDA=ON -G Ninja
```

### 3. Build
```bash
cmake --build build --config Release
```

### 4. Verification
```bash
./build/bin/llama-cli --help
```

### 5. Launching for Inference

#### Using `llama-cli` (Command Line Test)
For high-quality chat generation, use the following sampling parameters:

```bash
./build/bin/llama-cli \
  -m /hard/volume/data/llm-models/path/to/model.gguf \
  -p "User: Hello! Who are you?\nAssistant:" \
  -n 512 \
  --temp 0.7 \
  --top-p 0.9 \
  --repeat-penalty 1.1 \
  -ngl all \
  -c 4096
```

#### Using `llama-server` (OpenAI Compatible API)
To host the model as an API server:

```bash
./build/bin/llama-server \
  -m /hard/volume/data/llm-models/path/to/model.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl all \
  -c 8192 \
  --cont-batching
```

**Key Parameters:**
- `-ngl all`: Offload all layers to GPU (ensures A100 acceleration).
- `--temp 0.7`: Balanced creativity and coherence.
- `--repeat-penalty 1.1`: Prevents the model from getting stuck in loops.
- `-c <size>`: Context window size (adjust based on model capabilities and VRAM).
- `--cont-batching`: Enables continuous batching for the server (better throughput).