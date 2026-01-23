# Tutorial: Build `infer-dev` and run SGLang offline

This tutorial shows an **offline-first** workflow:

1) Use an **online** machine to build the Docker images and prepare all artifacts that require internet access.
2) Move the artifacts to an **offline** machine.
3) Run `infer-dev` and optionally auto-start **SGLang** on container boot, or start it manually after boot.

---

## 0) Prerequisites

### Host requirements (both online + offline machines)

- Docker Engine + Docker Compose v2 (`docker compose ...`)
- NVIDIA driver + NVIDIA Container Toolkit (so the container can see GPUs)
- Enough disk space
  - `infer-dev:stage-1` + `infer-dev:stage-2` images
  - SGLang offline bundle can be **very large** (Torch wheels, etc.)
  - Model weights (often tens of GB)

### Repo requirements (online machine)

- This repository checked out
- `pei-docker-cli` available on PATH (used to regenerate `docker-compose.yml` from `user_config.yml`)

---

## 1) Online machine: build the `infer-dev` images from scratch

> All commands below are run from the repo root unless stated otherwise.

### 1.1 Enter the environment folder

```bash
cd dockers/infer-dev
```

### 1.2 (Optional) Regenerate project artifacts from `user_config.yml`

If you changed `user_config.yml` (ports, mounts, scripts), regenerate derived files:

```bash
pei-docker-cli configure --with-merged
```

This rewrites (among others) `dockers/infer-dev/docker-compose.yml`, `dockers/infer-dev/merged.env`, and build/run scripts.

### 1.3 Build stage-1 (base layer)

Stage-2 uses `infer-dev:stage-1` as its base, so build stage-1 first:

```bash
docker compose --profile build-helper build stage-1
```

### 1.4 Build stage-2 (dev/runtime layer)

```bash
docker compose build stage-2
```

### 1.5 Export images for offline transfer

Save both images into a tarball you can copy to the offline machine:

```bash
docker save infer-dev:stage-1 infer-dev:stage-2 | gzip > infer-dev-images.tar.gz
```

---

## 2) Online machine: prepare the SGLang offline bundle (Pixi-pack)

Goal: keep the Docker image lightweight, and install SGLang **at runtime** from an **offline bundle**.

### 2.1 Install prerequisites on the online machine

You need `pixi` and `pixi-pack` on the **host** (not inside the container) to build the bundle.

Verify:

```bash
pixi --version
pixi-pack --version
```

If `pixi-pack` is missing, install it (example):

```bash
pixi global install pixi-pack
```

### 2.2 Build a self-extracting SGLang bundle (recommended for offline)

This produces a single `.sh` bundle (no extra tools needed in the offline container):

```bash
./dockers/infer-dev/host-scripts/build-sglang-bundle.sh --create-executable \
  -o dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh
```

Optional: record the sha256 for integrity/idempotency checks later:

```bash
sha256sum dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh
```

What you should transfer to offline:

- `dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh`

---

## 3) Online machine: prepare the model weights for offline use

SGLang config refers to model paths **inside the container**, so you must:

- download model weights on the online machine
- copy them to the offline machine
- mount them into the container at the expected path

### 3.1 Pick a target container path

This tutorial uses:

- container path: `/llm-models/GLM-4.7`

Your host can store weights anywhere, e.g.:

- host path (example): `/data/llm-models/GLM-4.7`

### 3.2 Download model weights (online)

Use your preferred downloader (Hugging Face / ModelScope / internal mirror). The important outcome is a local directory containing the full model weights.

After download, you should have something like:

```text
/data/llm-models/GLM-4.7/
  config.json
  tokenizer.json
  model.safetensors (or shards)
  ...
```

### 3.3 Transfer model weights to the offline machine

Copy the whole directory (e.g. with `rsync` or an external disk):

- `/data/llm-models/GLM-4.7` (online) → `/data/llm-models/GLM-4.7` (offline)

---

## 4) Offline machine: load images + prepare runtime files

### 4.1 Load the Docker images

Copy `infer-dev-images.tar.gz` to the offline machine, then:

```bash
docker load < infer-dev-images.tar.gz
```

Verify:

```bash
docker image ls infer-dev:stage-1 infer-dev:stage-2
```

### 4.2 Place the SGLang bundle in the mounted workspace

`infer-dev` mounts this directory:

- host: `dockers/infer-dev/.container/workspace`
- container: `/hard/volume/workspace`

Copy the prepared bundle to the offline repo checkout:

- `dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh`

So inside the container it is visible as:

- `/hard/volume/workspace/sglang-offline-bundle.sh`

---

## 5) Offline machine: auto-launch SGLang on container boot

### 5.1 Use (or create) an SGLang TOML config

Start from the example:

- `dockers/infer-dev/model-configs/sglang-glm-4.7-tp8.toml`

Key fields to check:

- `port = 30000` (container port)
- `model_path = "/llm-models/GLM-4.7"` (container mount path)
- `tp_size = <your GPU count>` (adjust to match your machine)

### 5.2 Run a container that installs SGLang + starts serving on boot

From `dockers/infer-dev/`:

```bash
docker compose run -d --service-ports --name infer-sglang \
  -v "$PWD/model-configs:/model-configs:ro" \
  -v "/data/llm-models/GLM-4.7:/llm-models/GLM-4.7:ro" \
  -e AUTO_INFER_SGLANG_BUNDLE_ON_BOOT=1 \
  -e AUTO_INFER_SGLANG_BUNDLE_PATH=/hard/volume/workspace/sglang-offline-bundle.sh \
  -e AUTO_INFER_SGLANG_ON_BOOT=1 \
  -e AUTO_INFER_SGLANG_CONFIG=/model-configs/sglang-glm-4.7-tp8.toml \
  stage-2 sleep infinity
```

Notes:

- The install target defaults to `/hard/volume/workspace/sglang-pixi-offline` (persisted on the host via the workspace mount).
- Helpers are always available inside the container:
  - `/soft/app/sglang/install-sglang-offline.sh`
  - `/soft/app/sglang/check-and-run-sglang.sh`

---

## 6) Offline machine: verify SGLang is serving

### 6.1 Check container logs (optional)

The default log file naming is:

- `/tmp/sglang-server-<instance_name>.log`

For the example config, the instance name is `glm_4_7_tp8`, so:

```bash
docker exec -it infer-sglang bash -lc 'tail -n 200 /tmp/sglang-server-glm_4_7_tp8.log'
```

### 6.2 Test the OpenAI-compatible endpoints from the host

This repo maps:

- host `11982` → container `30000`

Test:

```bash
curl http://127.0.0.1:11982/v1/models
```

Then a basic chat completion:

```bash
curl http://127.0.0.1:11982/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"glm-4.7","messages":[{"role":"user","content":"Hello"}],"max_tokens":64}'
```

If `/v1/models` responds and `/v1/chat/completions` returns JSON, SGLang is serving properly.

---

## 7) Offline machine: start container WITHOUT auto SGLang, then start manually

### 7.1 Start the container with SGLang auto-start disabled

Do not set `AUTO_INFER_SGLANG_*` vars:

```bash
docker compose run -d --service-ports --name infer-dev \
  -v "$PWD/model-configs:/model-configs:ro" \
  -v "/data/llm-models/GLM-4.7:/llm-models/GLM-4.7:ro" \
  stage-2 sleep infinity
```

### 7.2 Manually install SGLang from the offline bundle

```bash
docker exec -it \
  -e AUTO_INFER_SGLANG_BUNDLE_PATH=/hard/volume/workspace/sglang-offline-bundle.sh \
  infer-dev \
  /soft/app/sglang/install-sglang-offline.sh
```

### 7.3 Manually start serving from a TOML config

```bash
docker exec -it \
  -e AUTO_INFER_SGLANG_CONFIG=/model-configs/sglang-glm-4.7-tp8.toml \
  infer-dev \
  /soft/app/sglang/check-and-run-sglang.sh
```

If your config file is on the host, mount it in (example):

```bash
docker exec -it infer-dev bash -lc 'ls -la /model-configs'
```

---

## 8) Offline notes / troubleshooting

- **Bundle format**:
  - For offline environments, prefer the self-extracting bundle (`--create-executable`, ends with `.sh`).
  - If you use a `.tar/.tgz` bundle, `install-sglang-offline.sh` needs `pixi-unpack`. Its auto-download requires internet, so bring `pixi-unpack` with you and set `AUTO_INFER_SGLANG_PIXI_UNPACK_BIN`.
- **GPU visibility**:
  - Verify inside the container: `docker exec -it <name> nvidia-smi -L`
  - Per-instance GPU pinning is via TOML `gpu_ids` → `CUDA_VISIBLE_DEVICES`.
- **Ports**:
  - SGLang server port is the **container port** in the TOML (`port = 30000` by default here).
  - Host port is controlled by Compose mapping (`11982:30000` by default in this repo).
