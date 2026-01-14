# Repository Guidelines

## Project Structure & Module Organization

- `dockers/<env>/`: Docker Compose environments (e.g., `dockers/vllm`, `dockers/litellm`, `dockers/infer-dev`). Each env should include `README.md`, `docker-compose.yml`, and a tracked `env.example`.
- `src/dev_dockers/`: Minimal Python package scaffold (installable via Pixi).
- `tests/`: `unit/`, `integration/`, and `manual/` (manual files should be named `manual_*.py`).
- `models/`: Model bootstrap helpers and per-model folders (gitignored artifacts are expected).
- `extern/` + `magic-context/`: Git submodules and tracked third-party sources (avoid editing unless you intend to update the submodule).
- `context/`: Design notes, plans, logs, and task context used during development.

## Build, Test, and Development Commands

- `git submodule update --init --recursive`: Initialize/update submodules (`magic-context`, `extern/tracked/PeiDocker`).
- `pixi install`: Create the Python dev environment from `pyproject.toml`/`pixi.lock`.
- `pixi run pytest tests/unit`: Run fast, hermetic tests.
- `pixi run pytest tests/integration`: Run integration tests (may require external services).
- `source ./setup-envs.sh`: Set `CODEX_HOME` (when `.codex/` exists) and auto-detect proxy settings via `setup-proxy.sh`.
- Example Docker workflow:
  - `cd dockers/vllm && cp env.example .env && docker-compose up -d`
  - `cd dockers/litellm && cp env.example .env && docker-compose up -d`
  - `./dockers/infer-dev/build-merged.sh && ./dockers/infer-dev/run-merged.sh --shell`

## Coding Style & Naming Conventions

- Python: 4-space indentation, keep modules small and typed when practical.
- YAML: 2-space indentation; keep Compose files and `.env` variables aligned with each env’s `env.example`.
- Docker config “contract” (see `dockers/README.md`): use `HOST_PORT_*` / `CONTAINER_PORT_*` and `HOST_VOLUME_*` / `CONTAINER_VOLUME_*` for mappings.
- Shell scripts: prefer `#!/usr/bin/env bash` and `set -euo pipefail` for new scripts; mirror local style in existing files when editing.

## Commit & Pull Request Guidelines

- Commits commonly use Conventional Commits (e.g., `feat: ...`) and imperative subjects (e.g., `Update ...`). Prefer `feat|fix|docs|chore:` with a short, scoped summary.
- PRs should include: what environment(s) changed (`dockers/<env>`), any new/changed `.env` variables (update `env.example`), and reproduction/validation steps (commands to run). Never commit secrets (tokens, `.env`, private keys).

