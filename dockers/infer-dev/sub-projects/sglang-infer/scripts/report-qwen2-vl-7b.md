# Report: `models/qwen2-vl-7b` SGLang smoke test (cu126 + cu128)

Date: 2026-01-23

## Summary

Ran the repo smoke test script to (1) start an SGLang server, (2) send a real `/v1/chat/completions` request, (3) receive a valid response, for both:

- `default` environment (torch `2.9.1+cu126`)
- `cu128` environment (torch `2.9.1+cu128`)

## Notes about CuDNN check

The server fails to start with the default config because SGLang blocks `torch==2.9.1` when `torch.backends.cudnn.version() < 9.15` (see the stack trace in the earlier log `tmp/sglang-infer/qwen2-vl-7b-smoke-20260123-144646/sglang-default-qwen2-vl-7b.dQan5x.log`).

For this run, the check was bypassed by setting:

- `SGLANG_DISABLE_CUDNN_CHECK=1`

## Model

- Model path: `models/qwen2-vl-7b/source-data` (symlink to local weights)
- Served model name: `qwen2-vl-7b`

## Test run (logs + command)

- Log directory: `tmp/sglang-infer/qwen2-vl-7b-smoke-20260123-145556/`
- Smoke script: `dockers/infer-dev/sub-projects/sglang-infer/scripts/smoke-qwen2-vl-7b-cu126-then-cu128.sh`

Environment used for the run:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy \
  CUDA_VISIBLE_DEVICES=0,1 \
  SGLANG_TP_SIZE_CU126=2 \
  SGLANG_TP_SIZE_CU128=2 \
  SGLANG_BASE_PORT=30100 \
  SGLANG_DEVICE=cuda \
  SGLANG_DISABLE_CUDNN_CHECK=1 \
  HF_HUB_OFFLINE=1 \
  TRANSFORMERS_OFFLINE=1 \
  bash dockers/infer-dev/sub-projects/sglang-infer/scripts/smoke-qwen2-vl-7b-cu126-then-cu128.sh
```

## GPU usage evidence

From `tmp/sglang-infer/qwen2-vl-7b-smoke-20260123-145556/nvidia-smi.csv`:

- Peak GPU util: GPU0=100%, GPU1=100%
- Peak memory used: GPU0=17020 MiB, GPU1=16976 MiB

## Request + Response (cu126 / `default`)

Request sent (from the smoke script):

```json
{
  "model": "qwen2-vl-7b",
  "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
  "max_tokens": 64,
  "temperature": 0
}
```

Response received (captured in `tmp/sglang-infer/qwen2-vl-7b-smoke-20260123-145556/smoke-console.log`):

```json
{"id":"e87468f1c6b847ba99036a3aa37141dc","object":"chat.completion","created":1769180234,"model":"qwen2-vl-7b","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!","reasoning_content":null,"tool_calls":null},"logprobs":null,"finish_reason":"stop","matched_stop":151645}],"usage":{"prompt_tokens":26,"total_tokens":29,"completion_tokens":3,"prompt_tokens_details":null,"reasoning_tokens":0},"metadata":{"weight_version":"default"}}
```

## Request + Response (cu128 / `cu128`)

Request sent (same payload as cu126):

```json
{
  "model": "qwen2-vl-7b",
  "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
  "max_tokens": 64,
  "temperature": 0
}
```

Response received (captured in `tmp/sglang-infer/qwen2-vl-7b-smoke-20260123-145556/smoke-console.log`):

```json
{"id":"68a05a49df7f45d3875119b60d0bd84a","object":"chat.completion","created":1769180279,"model":"qwen2-vl-7b","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!","reasoning_content":null,"tool_calls":null},"logprobs":null,"finish_reason":"stop","matched_stop":151645}],"usage":{"prompt_tokens":26,"total_tokens":29,"completion_tokens":3,"prompt_tokens_details":null,"reasoning_tokens":0},"metadata":{"weight_version":"default"}}
```
