# vLLM Docker Setup

This directory contains the Docker Compose configuration to run a high-performance vLLM inference server, specifically optimized for Video-Language Models (like Qwen2-VL).

## Prerequisites

*   Docker & Docker Compose installed.
*   NVIDIA Container Toolkit installed and configured.
*   NVIDIA GPUs (Pascal or newer).

## Quick Start

1.  **Configure Environment:**
    Copy the example environment file:
    ```bash
    cp env.example .env
    ```
    Edit `.env` to set your Hugging Face token (if needed) and adjust GPU settings.

2.  **Start Service:**
    ```bash
    docker-compose up -d
    ```

3.  **Test:**
    ```bash
    curl http://localhost:8000/v1/models
    ```

## Video Input Note

To use video input with Qwen2-VL or similar models:
*   Ensure `--enable-mm-embeds` is in the command (enabled by default in this compose).
*   Use the OpenAI-compatible Chat Completions API.

## Local Media

The configuration mounts `~/.cache/huggingface` to `/root/.cache/huggingface` inside the container.
To use local video files, place them in your host's cache dir (or add another volume mount) and refer to them via the `--allowed-local-media-path` configuration in `docker-compose.yml`.
