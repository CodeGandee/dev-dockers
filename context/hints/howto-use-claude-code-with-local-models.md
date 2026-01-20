# How to Use Claude Code with Local Models (via LiteLLM)

This guide explains how to configure `Claude Code` (the CLI tool) to use a local LLM (hosted by `llama.cpp` or similar) via `LiteLLM` as a bridge.

> Note: In this repo, `dockers/infer-dev` can auto-start an in-container LiteLLM + telemetry proxy.
> See `dockers/infer-dev/README.md` and `/soft/app/litellm/check-and-run-litellm.sh` inside the container.

## Overview

`Claude Code` communicates with the Anthropic API. To use a local model, we need to:
1.  **Bridge Protocols**: Convert Anthropic API calls to OpenAI-compatible API calls (handled by `LiteLLM`).
2.  **Mock Telemetry**: `Claude Code` sends telemetry to `/api/event_logging/batch`, which local servers usually don't support. We must mock this to prevent errors/hangs.

## Prerequisites

- **LiteLLM**: Installed (`pip install litellm` or via `uv`).
- **Local Model**: Running `llama-server` (or similar) exposing an OpenAI-compatible endpoint (e.g., `http://127.0.0.1:11980/v1`).
- **Claude Code**: Installed (`npm install -g @anthropic-ai/claude-code`).

## Step 1: Configure LiteLLM

Create a `litellm_config.yaml` to map Claude model names to your local model.

```yaml
model_list:
  # Map specific models requested by Claude Code
  - model_name: claude-3-5-sonnet-20240620
    litellm_params:
      model: openai/glm4  # Replace with your local model alias/name
      api_base: http://127.0.0.1:11980/v1
      api_key: dummy
  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: openai/glm4
      api_base: http://127.0.0.1:11980/v1
      api_key: dummy
  # Add other aliases as needed (e.g. claude-haiku-...)
general_settings:
  master_key: sk-litellm-master
```

Start LiteLLM:
```bash
litellm --config litellm_config.yaml --port 8000
```

## Step 2: Handle Telemetry (The Mock Proxy)

`Claude Code` insists on sending logs to `/api/event_logging/batch`. `LiteLLM` returns 404, which may cause `Claude Code` to hang or fail. You need a simple proxy to intercept this.

Here is a minimal Python script (`proxy.py`) to handle this:

```python
import http.server
import socketserver
import requests

LITELLM_URL = "http://127.0.0.1:8000"
PORT = 8001

class RequestHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        # Mock the logging endpoint
        if self.path == "/api/event_logging/batch":
            self.send_response(200)
            self.end_headers()
            return

        # Forward everything else to LiteLLM
        # Note: A production implementation should stream the response
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            
            resp = requests.post(
                f"{LITELLM_URL}{self.path}",
                data=post_data,
                headers={k: v for k, v in self.headers.items() if k.lower() != 'host'},
                stream=True
            )
            
            self.send_response(resp.status_code)
            for k, v in resp.headers.items():
                self.send_header(k, v)
            self.end_headers()
            
            for chunk in resp.iter_content(chunk_size=4096):
                self.wfile.write(chunk)
        except Exception as e:
            self.send_error(500, str(e))

    def do_GET(self):
        # Forward GET requests (e.g. /models)
        try:
            resp = requests.get(f"{LITELLM_URL}{self.path}")
            self.send_response(resp.status_code)
            self.end_headers()
            self.wfile.write(resp.content)
        except Exception as e:
            self.send_error(500, str(e))

print(f"Proxy running on port {PORT} -> LiteLLM {LITELLM_URL}")
http.server.HTTPServer(("", PORT), RequestHandler).serve_forever()
```

Run this proxy: `python3 proxy.py`

## Step 3: Run Claude Code

Configure `Claude Code` to use your proxy (port 8001) instead of the real API.

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:8001
export ANTHROPIC_API_KEY=sk-litellm-master

claude -p "Hello world"
```

## Troubleshooting

- **Invalid Model Name**: If `Claude Code` fails with "Invalid model name", check `litellm` logs to see what model name was requested, and add it to your `litellm_config.yaml`.
- **Connection Refused**: Ensure `llama-server`, `litellm`, and `proxy.py` are all running.
