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
- **Persistent mounts**:
  - `dockers/infer-dev/.container/app` → `/hard/volume/app`
  - `dockers/infer-dev/.container/data` → `/hard/volume/data`
  - `dockers/infer-dev/.container/workspace` → `/hard/volume/workspace`
  - Host models dir (see `user_config.yml`) → `/hard/volume/data/llm-models`
- **Auto-launch llama.cpp server**: set `AUTO_INFER_LLAMA_CPP_CONFIG` to a TOML file (see `examples/llama_config.toml`) and the entry hook will start the configured `llama-server` instances.
- **Dev tooling in stage-2** (installed via `user_config.yml`): Pixi, Node.js, Bun, and agent CLIs (as configured).

## Quick start

```bash
docker compose build stage-2
docker compose up -d
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
