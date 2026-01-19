# GLM-4.7 GGUF (Local Reference)

Reference to the local GLM-4.7 GGUF model directory, containing multiple quantizations (e.g., Q2_K, Q4_K_M).

## Setup

Run `./bootstrap.sh` to link `source-data` to the local storage location.

## Locations

- Source: `/data2/huangzhe/llm-models/GLM-4.7-GGUF`

## Usage Guide

GLM-4.7 is a large model (approx. 350B parameters) and requires significant resources.

### Configuration
When running with `llama-server` (e.g., in `infer-dev`), ensure you:
1.  Enable **Jinja templates** (`jinja = true`).
2.  Do **not** force a hardcoded `chat_template` name (let it detect from GGUF).
3.  Use sufficient GPUs (e.g., 8x 3090/4090 for Q2_K quantization).
4.  Allow sufficient time for loading (5-10 minutes).

### Interaction (Curl)
You **must** provide explicit **stop tokens** to prevent the model from generating garbage or hallucinating.

**Stop tokens:** `["<|user|>", "<|observation|>"]`

Example request:

```bash
curl http://127.0.0.1:11980/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
  "model": "glm4",
  "messages": [{"role": "user", "content": "Hello! Please introduce yourself."}
  ],
  "max_tokens": 256,
  "stop": ["<|user|>", "<|observation|>"]
}'
```