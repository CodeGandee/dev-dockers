# dev-dockers

**Project Overview**

`dev-dockers` is a repository for managing Docker configurations for various development tasks, with a primary focus on Large Language Model (LLM) serving and proxying. It utilizes `PeiDocker` for automation and adheres to strict configuration standards for consistency.

**Key Technologies:**
*   **Docker & Docker Compose**: Core container orchestration.
*   **PeiDocker**: Automation framework for generating Docker configurations (included as a submodule).
*   **Pixi**: Python environment and task management.
*   **vLLM & LiteLLM**: Primary supported environments.

## Directory Structure

*   `dockers/`: Contains specific environment configurations (e.g., `vllm/`, `litellm/`).
*   `context/`: Centralized knowledge base and documentation.
*   `extern/tracked/PeiDocker/`: Submodule for the `PeiDocker` automation tool.
*   `src/`: Source code for the `dev_dockers` python package.
*   `scripts/`: Utility scripts.
*   `setup-envs.sh`: Script to initialize environment variables and proxies.

## Building and Running

### Prerequisites

1.  **Pixi**: Ensure `pixi` is installed.
2.  **Environment Setup**:
    ```bash
    source setup-envs.sh
    ```
    This configures proxies and environment variables like `CODEX_HOME`.

### Using Docker Environments

Navigate to a specific environment directory in `dockers/` (e.g., `dockers/vllm/`).

1.  **Configure Environment**:
    Copy `env.example` to `.env` and modify it.
    ```bash
    cp env.example .env
    # Edit .env to set ports, volumes, etc.
    ```

2.  **Run with Docker Compose**:
    ```bash
    docker compose up -d
    ```

### Python Development

Install dependencies and environment using Pixi:

```bash
pixi install
```

Run tests (if available):

```bash
pixi run test
```

## Development Conventions

### Docker Configuration Contracts

All Docker environments in `dockers/` must adhere to the strict contracts defined in `dockers/README.md`:

1.  **Resource Mapping**:
    *   **Ports**: Use `HOST_PORT_<PURPOSE>` and `CONTAINER_PORT_<PURPOSE>`.
    *   **Volumes**: Use `HOST_VOLUME_<PURPOSE>` and `CONTAINER_VOLUME_<PURPOSE>`.
2.  **Script Organization**:
    *   `container-scripts/`: Scripts to run inside the container.
    *   `host-scripts/`: Scripts to run on the host.
3.  **Documentation**:
    *   Every directory must have a `README.md` and `env.example`.

### Submodules & Dependencies

*   **PeiDocker**: Located in `extern/tracked/PeiDocker`. It is installed as an editable dependency in `pyproject.toml`.
*   **Adding Dependencies**: Use `pixi add` for Python packages.

### Context Directory

Use the `context/` directory for all documentation, plans, and AI context storage. Follow the naming conventions in `context/README.md` (e.g., `howto-`, `task-`, `prompt-`).

## Testing and Temporary Files

When running tests or generating temporary scripts/outputs, always use the `tmp/` directory. Create a subdirectory for your specific task to avoid clutter.

*   **Location**: `tmp/<task-name>/`
*   **Git Behavior**: The `tmp/` directory is ignored by git.
