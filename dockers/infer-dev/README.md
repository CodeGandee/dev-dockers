# infer-dev (Inference Development Container)

`dockers/infer-dev` provides a GPU-enabled “inference development” container: a persistent, SSH-accessible CUDA Ubuntu environment for interactively building and running local LLM inference stacks (not just a single service).

It is generated/configured via **PeiDocker** and uses a 2-stage image:
- **Stage 1** (`infer-dev:stage-1`): system layer (CUDA base, SSH, APT/proxy helpers).
- **Stage 2** (`infer-dev:stage-2`): app/dev layer (developer tools and runtime hooks).

## What it’s for

- Experimenting with `llama.cpp` and `vLLM` inside a consistent CUDA environment.
- Keeping work persistent via host-mounted volumes for code/data/workspace and local model storage.
- Optionally auto-starting one or more `llama-server` instances on container entry.

## Key features (recent work)

- **CUDA + NVIDIA GPU** support (Compose requests all GPUs).
- **Storage + mounts**
  - `storage.app` and `storage.data` use `image` storage (not host-mounted).
  - `storage.workspace` is host-mounted: `dockers/infer-dev/.container/workspace` → `/hard/volume/workspace`.
  - Models are mounted via `stage_2.mount` (example: `/data1/huangzhe/llm-models/GLM-4.7-GGUF` → `/llm-models/GLM-4.7-GGUF`). Do **not** mount the entire host model tree.
- **Port mapping**
  - Host `11980` → container `8080` (llama-server).
- **Optional auto-launch llama.cpp server**:
  - Set `AUTO_INFER_LLAMA_CPP_ON_BOOT=1` (or `true`) to enable auto-start on container boot.
  - Set `AUTO_INFER_LLAMA_CPP_CONFIG` to a TOML file to define one or more `llama-server` instances.
  - If `AUTO_INFER_LLAMA_CPP_ON_BOOT` is unset/false, nothing auto-starts; run `/soft/app/llama-cpp/check-and-run-llama-cpp.sh` manually after boot.
- **Optional on-boot llama.cpp package install**
  - Set `AUTO_INFER_LLAMA_CPP_PKG_PATH` to a mounted archive (`.tar`, `.tar.gz`/`.tgz`, `.zip`) containing:
    - `README*` at archive root
    - `bin/llama-server` and the required `bin/*.so*` in the same folder
  - On boot, the archive is copied to `/soft/app/cache/` and extracted into `/soft/app/llama-cpp/` (idempotent via sha256).
- **Dev tooling in stage-2** (installed via `user_config.yml`): Pixi, Node.js, Bun, and agent CLIs (as configured).

## Quick start

```bash
docker compose build stage-2
docker compose up -d
```

## llama.cpp inference

Example config: `dockers/infer-dev/model-configs/glm-4.7-q2k.toml` (GLM-4.7 Q2_K, sharded GGUF).

Run an auto-start container (publishes port `11980` and mounts the config directory):

```bash
docker compose run -d --service-ports --name infer-glm \
  -v "$PWD/dockers/infer-dev/model-configs:/model-configs:ro" \
  -e AUTO_INFER_LLAMA_CPP_ON_BOOT=1 \
  -e AUTO_INFER_LLAMA_CPP_CONFIG=/model-configs/glm-4.7-q2k.toml \
  stage-2 sleep infinity
```

Verify:

```bash
curl http://127.0.0.1:11980/v1/models
curl http://127.0.0.1:11980/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "glm4",
  "messages": [{"role": "user", "content": "Hello"}],
  "max_tokens": 64
}'
```

## Editing configuration (important)

PeiDocker projects can be re-created/regenerated, and `user_config.yml` may be overwritten during that process. To keep your changes durable:

1. Edit `dockers/infer-dev/user_config.persist.yml`
2. Copy it over the active config before running PeiDocker:
   ```bash
   cp dockers/infer-dev/user_config.persist.yml dockers/infer-dev/user_config.yml
   ```

After changing `user_config.yml` or anything under `dockers/infer-dev/installation/`, you must run:

```bash
pei-docker-cli configure -p dockers/infer-dev
```

Otherwise the generated artifacts (notably `dockers/infer-dev/docker-compose.yml`, and optionally `merged.*`) will be stale. See `dockers/infer-dev/PEI-DOCKER-USAGE-GUIDE.md` for details.

To use the merged single-image workflow:
```bash
./build-merged.sh
./run-merged.sh --shell
```

Note: do not commit secrets (`.env`, tokens, private keys). Use `env.example`/config templates instead.
