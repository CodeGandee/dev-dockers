# Docker Environments

This directory contains Docker Compose configurations for various development and service environments used in this project.

## Available Environments

- **litellm/**: Configuration for LiteLLM, an OpenAI-compatible proxy server for various LLM backends.
- **vllm/**: Configuration for vLLM, a high-throughput and memory-efficient LLM inference engine.

## Configuration Contracts & Standards

To ensure consistency and flexibility across different environments, all Docker definitions in this project adhere to the following contracts:

### 1. Resource Mapping (Ports & Volumes)

All resource mappings between the host and container must be configurable via a `.env` file in the respective directory.

*   **Ports:**
    *   Use `HOST_PORT_<PURPOSE>` for the port exposed on the host machine.
    *   Use `CONTAINER_PORT_<PURPOSE>` for the port listening inside the container.
    *   *Default:* Container-side ports should default to the application's standard port (e.g., 8000 for vLLM) if not specified.

*   **Volumes:**
    *   Use `HOST_VOLUME_<PURPOSE>` for the directory path on the host machine.
    *   Use `CONTAINER_VOLUME_<PURPOSE>` for the directory path inside the container.
    *   *Default:* Container-side paths should default to standard locations (e.g., `/root/.cache/huggingface`).

**Example `.env` snippet:**
```dotenv
# Port Configuration
HOST_PORT_API=8080
CONTAINER_PORT_API=4000

# Volume Configuration
HOST_VOLUME_MODELS=/data/models
CONTAINER_VOLUME_MODELS=/app/models
```

### 2. Script Organization

Scripts associated with the Docker environment must be organized based on their execution context:

*   **`container-scripts/`**: Place scripts that will be copied **into** the container image or mounted and executed inside the container here.
*   **`host-scripts/`**: Place scripts that are intended to be executed on the **host** machine (e.g., setup, teardown, or management scripts) here.

### 3. Environment Configuration Examples

*   Each Docker environment directory **must** contain an `env.example` file.
*   This file should illustrate all available environment variables and their purpose.
*   The `env.example` file **must** be tracked by git to serve as a template for users.

### 4. Documentation

*   Each subdirectory (e.g., `dockers/vllm/`) **must** contain a `README.md` file.
*   This README should explain the specific service, how to configure it, available environment variables, and usage instructions.
