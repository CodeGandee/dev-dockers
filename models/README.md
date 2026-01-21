# External Models

This directory contains external, third-party and/or machine-local model assets. Only small metadata and bootstrap scripts are committed.

Managed references:

- `qwen3-0.6b` – Qwen 2.5 (?) 0.6B model (Folder name says Qwen3, needs verification).
  - Source: Local storage `/data1/huangzhe/llm-models/qwen3-0.6b`
  - Local path: `models/qwen3-0.6b`
  - `source-data`: Symlink to the local model directory.

- `qwen2-vl-7b` – Qwen2-VL-7B-Instruct (vision-language).
  - Source: Local storage `/data2/huangzhe/llm-models/Qwen2-VL-7B-Instruct`
  - Local path: `models/qwen2-vl-7b`
  - `source-data`: Symlink to the local directory.

- `glm-4.7` – GLM-4.7 GGUF collection (Q2_K, Q4_K_M).
  - Source: Local storage `/data2/huangzhe/llm-models/GLM-4.7-GGUF`
  - Local path: `models/glm-4.7`
  - `source-data`: Symlink to the local directory.

To (re)populate everything, run:

```bash
bash models/bootstrap.sh
```
