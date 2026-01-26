# Report: `models/qwen2-vl-7b` SGLang smoke test (cu128 default)

Date: 2026-01-26

## Summary

Verified that `dockers/infer-dev/sub-projects/sglang-infer` (cu128-only default env) can:

1) start an SGLang server for `models/qwen2-vl-7b`,
2) serve OpenAI-compatible endpoints, and
3) return a valid response for a real `/v1/chat/completions` request.

## Notes about CuDNN check

SGLang blocks `torch==2.9.1` when `torch.backends.cudnn.version() < 9.15` due to a known PyTorch/CuDNN issue.

For this test run, the check was bypassed by setting:

- `SGLANG_DISABLE_CUDNN_CHECK=1` (the smoke script defaults this to `1`)

## Model

- Model path: `models/qwen2-vl-7b/source-data` (symlink to local weights)
- Served model name: `qwen2-vl-7b`

## Test run (logs + command)

- Log directory: `tmp/sglang-infer/qwen2-vl-7b-smoke-cu128-20260126-105100/`
- Smoke script: `dockers/infer-dev/sub-projects/sglang-infer/scripts/smoke-qwen2-vl-7b-cu128.sh`

Environment used for the run:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy -u NO_PROXY -u no_proxy \
  CUDA_VISIBLE_DEVICES=0,1 \
  SGLANG_TP_SIZE=2 \
  SGLANG_DEVICE=cuda \
  HF_HUB_OFFLINE=1 \
  TRANSFORMERS_OFFLINE=1 \
  bash dockers/infer-dev/sub-projects/sglang-infer/scripts/smoke-qwen2-vl-7b-cu128.sh
```

Key runtime values from the smoke output:

- `torch 2.9.1+cu128` (CUDA `12.8`)
- bound to `127.0.0.1:<random>` (this run used port `38086`)
- tensor parallel: `2`

## GPU usage evidence

From `tmp/sglang-infer/qwen2-vl-7b-smoke-cu128-20260126-105100/nvidia-smi.csv`:

- Peak GPU util: GPU0=43%, GPU1=43%
- Peak memory used: GPU0=16712 MiB, GPU1=16974 MiB

## Request + Response

Request sent (captured from the smoke script):

```json
{
  "model": "qwen2-vl-7b",
  "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
  "max_tokens": 64,
  "temperature": 0
}
```

Response received (captured in `tmp/sglang-infer/qwen2-vl-7b-smoke-cu128-20260126-105100/smoke-console.log`):

```json
{"id":"e60c7ebe86d84daf9b622ffaace0fb4f","object":"chat.completion","created":1769424702,"model":"qwen2-vl-7b","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!","reasoning_content":null,"tool_calls":null},"logprobs":null,"finish_reason":"stop","matched_stop":151645}],"usage":{"prompt_tokens":26,"total_tokens":29,"completion_tokens":3,"prompt_tokens_details":null,"reasoning_tokens":0},"metadata":{"weight_version":"default"}}
```
