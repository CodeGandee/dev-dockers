# Qwen2-VL 7B Instruct (Local Reference)

Reference to the local Qwen2-VL-7B-Instruct model directory.

## Setup

Run `./bootstrap.sh` to link `source-data` to the local storage location.

## Locations

- Source: `/data2/huangzhe/llm-models/Qwen2-VL-7B-Instruct`

## Notes

- This is a multi-modal (vision-language) model. It is typically served via vLLM (see `dockers/vllm/`).
- If you want to use a local path with vLLM, you can set `MODEL_NAME` to the linked directory path (e.g. `.../models/qwen2-vl-7b/source-data`) and ensure it is visible inside the serving container (via bind mount).

