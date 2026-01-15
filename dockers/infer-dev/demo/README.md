# infer-dev demos

This folder contains small, runnable demos for `dockers/infer-dev` that use **plain `docker run`** (no `docker compose`).

## Files

- `start-docker-with-auto-inference.sh`: starts `infer-dev:stage-2`, triggers **llama.cpp bundle install** on boot, and optionally triggers **auto serving** via a TOML config.

## start-docker-with-auto-inference.sh

### What it does

- Runs `infer-dev:stage-2` with:
  - `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1`
  - `AUTO_INFER_LLAMA_CPP_PKG_PATH=/tmp/<pkg>`
- Mounts your `--llama-pkg` archive into the container at `/tmp/<pkg>` (read-only).
- If `--llama-auto-serve on`, also sets:
  - `AUTO_INFER_LLAMA_CPP_ON_BOOT=1`
  - `AUTO_INFER_LLAMA_CPP_CONFIG=/tmp/<config>`
  and mounts `--llama-config` into `/tmp/<config>` (read-only).
- If `--model-dir` is provided, mounts it to `/llm-models/<basename>` (read-only).
- Publishes container port `8080` (llama-server) to `--port` on the host.

### Usage

```bash
# Print the docker run command without executing it
./dockers/infer-dev/demo/start-docker-with-auto-inference.sh --dry-run \
  --port 11980 \
  --llama-auto-serve on \
  --llama-pkg dockers/infer-dev/.container/workspace/llama-cpp-pkg.tgz \
  --llama-config dockers/infer-dev/model-configs/glm-4.7-q2k.toml \
  --model-dir /data1/huangzhe/llm-models/GLM-4.7-GGUF

# Actually run it
./dockers/infer-dev/demo/start-docker-with-auto-inference.sh \
  --port 11980 \
  --llama-auto-serve on \
  --llama-pkg dockers/infer-dev/.container/workspace/llama-cpp-pkg.tgz \
  --llama-config dockers/infer-dev/model-configs/glm-4.7-q2k.toml \
  --model-dir /data1/huangzhe/llm-models/GLM-4.7-GGUF
```

### After start

- Follow logs: `docker logs -f infer-dev-auto-infer`
- Stop/remove: `docker rm -f infer-dev-auto-infer`
- If auto-serve is off, start serving manually:
  - `docker exec -it infer-dev-auto-infer /soft/app/llama-cpp/check-and-run-llama-cpp.sh`

