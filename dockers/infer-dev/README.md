# Infer-Dev Environment

A high-performance development environment based on CUDA 12.6, cuDNN, and Ubuntu 24.04, optimized for LLM inference and AI agent development.

## Configuration

This project uses `PeiDocker` for configuration management.

*   **`user_config.persist.yml`**: This is the persistent source of truth for your configuration. To apply changes, copy this to `user_config.yml` before running the configure command.
*   **`user_config.yml`**: The file used by `pei-docker-cli`. **Warning**: This file may be overwritten by `pei-docker-cli create`.

### To apply configuration:
```bash
cp user_config.persist.yml user_config.yml
pixi run pei-docker-cli configure -p . --with-merged
```

## Tools Installed (for user 'me')

*   **uv**: Fast Python package manager (Stage 1).
*   **pixi**: Conda-compatible package manager (Stage 2).
*   **claude-code**: Anthropic's Claude CLI (Stage 2).
*   **codex-cli**: OpenAI's Codex CLI (Stage 2).

## Resource Mapping

*   **SSH**: Port 22 (container) -> `${HOST_PORT_SSH:-2222}` (host).
*   **Proxy**: Uses `${HOST_PORT_PROXY:-7890}`.
*   **Storage**:
    *   `.container/app` -> `/soft/app`
    *   `.container/data` -> `/soft/data`
    *   `.container/workspace` -> `/soft/workspace`
    *   `.container/home-me` -> `/home/me`

## Build and Run

### Using Docker Compose
```bash
docker compose build stage-2
docker compose up -d stage-2
```

### Using Merged Build (Standalone)
```bash
./build-merged.sh
./run-merged.sh
```
