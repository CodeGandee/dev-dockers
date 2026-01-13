# Setup llama.cpp (2026-01-13)

## Environment
- Container: `infer-dev:stage-2`
- User: `me`
- Workspace: `/hard/volume/workspace/llama-cpp` (mapped from host `dockers/infer-dev/.container/workspace/llama-cpp`)

## Steps

### 1. Install Build Tools
Using `pixi` to install `cmake` and `ninja`.

```bash
export PATH=$HOME/.pixi/bin:$PATH
pixi global install cmake ninja
```

### 2. Configure Build (CUDA)
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
