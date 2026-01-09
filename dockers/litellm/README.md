# LiteLLM Proxy Docker Setup

This directory contains the Docker Compose configuration to run **LiteLLM**, acting as a unified API Gateway for your various local inference services (vLLM, llama.cpp, etc.).

## Purpose

It consolidates multiple OpenAI-compatible endpoints into a single, standardized API endpoint.

*   `vLLM` (Video/High-Performance) -> `http://localhost:4000/v1`
*   `llama.cpp` (CPU/Edge) -> `http://localhost:4000/v1`

## Quick Start

1.  **Configure Environment:**
    ```bash
    cp env.example .env
    ```
    Update the `VLLM_API_BASE` and `LLAMACPP_API_BASE` to point to your actual running services.
    *   If running on the same host, `http://host.docker.internal:PORT/v1` usually works.

2.  **Start Proxy:**
    ```bash
    docker-compose up -d
    ```

3.  **Test:**
    ```bash
    # List available models
    curl http://localhost:4000/v1/models -H "Authorization: Bearer sk-my-secret-key-123"

    # Chat with vLLM model
    curl http://localhost:4000/v1/chat/completions \
      -H "Authorization: Bearer sk-my-secret-key-123" \
      -H "Content-Type: application/json" \
      -d 
      '{
        "model": "qwen2-vl",
        "messages": [{"role": "user", "content": "Hello!"}]
      }'
    ```

## Configuration

Edit `litellm_config.yaml` to add or modify model routes. The docker container automatically reloads changes to this file (in most configurations, or requires a restart).

```
