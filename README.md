# dev-dockers

This repository contains Docker configurations for various development tasks.

## Structure

The repository is organized as a set of docker configuration directories.

`dockers/<docker-dir>/`

Each directory contains relevant Dockerfiles, Docker Compose files, and related scripts for a specific environment or tool.

## llama.cpp inference (infer-dev)

`dockers/infer-dev` is a PeiDocker-based CUDA dev container that can auto-launch `llama-server` on startup.

### 1) Configure (required after changes)

```bash
# Keep durable edits in user_config.persist.yml, then copy to user_config.yml
cp dockers/infer-dev/user_config.persist.yml dockers/infer-dev/user_config.yml

# Regenerate docker-compose.yml / merged.* from user_config.yml
pixi run pei-docker-cli configure -p dockers/infer-dev --with-merged
```

### 2) Build the images

```bash
docker compose -f dockers/infer-dev/docker-compose.yml build stage-1
docker compose -f dockers/infer-dev/docker-compose.yml build stage-2
```

### 3) Start llama-server via TOML (auto-launch hook)

The entry hook can auto-start `llama-server` instances, but it is **off by default**.

- Set `AUTO_INFER_LLAMA_CPP_ON_BOOT=1` (or `true`) to enable auto-start on boot.
- Set `AUTO_INFER_LLAMA_CPP_CONFIG` to point at a TOML file with instance definitions.
- If auto-start is disabled, you can run `/soft/app/llama-cpp/check-and-run-llama-cpp.sh` manually inside the container.

Example (GLM-4.7 Q2_K):
- Config: `dockers/infer-dev/model-configs/glm-4.7-q2k.toml`
- Host port `11980` → container port `8080` (see `dockers/infer-dev/docker-compose.yml`)

Run with the env var set (publish service ports and mount the config directory into the container):

```bash
docker compose -f dockers/infer-dev/docker-compose.yml run -d --service-ports --name infer-glm \
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

Notes:
- The sample config mounts a specific model directory to `/llm-models/...` (not the entire host model tree); adjust `dockers/infer-dev/user_config.persist.yml` + rerun `pei-docker-cli configure` to test other models.
- `AUTO_INFER_LLAMA_CPP_PKG_PATH` + `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1|true` installs a prebuilt llama.cpp bundle into `/soft/app/llama-cpp` on boot (archive is cached under `/soft/app/cache`). If auto-install is off, run `/soft/app/llama-cpp/get-llama-cpp-pkg.sh` inside the container.
