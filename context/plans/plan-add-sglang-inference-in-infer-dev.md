# Plan: Add SGLang Pixi bundle + auto-serve for infer-dev

## HEADER

- **Purpose**: Add an opt-in mechanism in `dockers/infer-dev` to (1) install SGLang + its CUDA kernel dependencies using Pixi at runtime (not baked into the image) and (2) start one or more SGLang OpenAI-compatible servers from a TOML config on container boot or manually after boot.
- **Status**: Draft
- **Date**: 2026-01-21
- **Dependencies**:
  - `dockers/infer-dev/installation/stage-2/custom/infer-dev-entry.sh` (boot hook wiring pattern)
  - `dockers/infer-dev/installation/stage-2/custom/install-vllm-offline.sh` (Pixi offline install pattern)
  - `dockers/infer-dev/installation/stage-2/custom/check-and-run-vllm.sh` (TOML runner pattern: multi-instance, per-GPU, logs)
  - `dockers/infer-dev/installation/stage-2/system/pixi/install-pixi.bash` (Pixi availability in stage-2)
  - `context/plans/done/plan-auto-install-llama-cpp-pkg-on-boot.md` (boot-time “install package then optionally serve” contract)
  - `context/plans/plan-add-vllm-package-auto-infer-infer-dev.md` (Pixi-pack + on-boot install/serve design)
  - `context/hints/howto-host-glm-4-7-with-sglang-on-cuda-12-6.md` (GLM-4.7 flags + baseline install guidance)
  - SGLang official docs:
    - Install: https://docs.sglang.io/get_started/install.html
    - Server arguments: https://docs.sglang.io/advanced_features/server_arguments.html
    - GLM-4.7-Flash cookbook: https://cookbook.sglang.io/docs/autoregressive/GLM/GLM-4.7-Flash
  - Pixi official docs:
    - Manifest (`pypi-options`/`pypi-dependencies`): https://pixi.sh/latest/reference/pixi_manifest/
    - `pixi-pack` (PyPI wheel support / `--ignore-pypi-non-wheel`): https://pixi.prefix.dev/latest/deployment/pixi_pack/
- **Target**: AI engineers using `dockers/infer-dev` for local GPU inference who want SGLang available without making the Docker image heavy.

---

## 1. Purpose and Outcome

Success looks like:

- `infer-dev:stage-2` remains lightweight: it includes Pixi and small helper scripts/config templates, but does not include SGLang, FlashInfer, Torch wheels, or model weights.
- Users can choose one of two installation modes:
  1. **On-boot install**: set env vars and mount a bundle / wheelhouse; the container installs SGLang into a workspace-backed location and optionally starts serving.
  2. **Manual install**: after boot, users run a helper under `/soft/app/sglang/` to install/update the environment and then start serving.
- Users can start SGLang serving via a **TOML config** (multi-instance, per-instance `CUDA_VISIBLE_DEVICES`, log files), similar to the existing `llama.cpp` and `vLLM` flows.
- A documented “GLM-4.7 on CUDA 12.6” config works (at least for a single-node multi-GPU setup), including:
  - `--reasoning-parser glm45`
  - `--tool-call-parser glm47`

Non-goals (for this initial plan):

- Building SGLang from source in-container by default (keep source-build as an explicit opt-in fallback).
- Multi-node orchestration (leave that to SGLang’s own `--dist-init-addr/--nnodes` workflows).

## 2. Implementation Approach

### 2.1 High-level flow

1. **Add a Pixi template project for SGLang** (manifest + lock only; no `.pixi/`):
   - `pixi.toml` pins a known-good SGLang version and a compatible Torch/CUDA wheel channel.
   - `pypi-options` includes:
     - `extra-index-urls` for the correct CUDA PyTorch wheels (e.g. cu126)
     - `find-links` for FlashInfer wheels (version pinned to match Torch ABI)
   - Provide a `verify` task that imports `torch`, `sglang`, and validates CUDA availability.
   - Include a note/option to switch kernels if FlashInfer is problematic on a given GPU (e.g. `--attention-backend triton --sampling-backend pytorch`).

2. **Host-side bundle builder (recommended)**:
   - Add `build-sglang-bundle.sh` modeled after `build-vllm-bundle.sh`.
   - Uses `pixi-pack` to produce a tar containing:
     - `channel/` (conda packages + repodata)
     - packed PyPI wheels (only wheels; source dists rejected or ignored)
     - `environment.yml` and metadata
   - Uses persistent caches in `dockers/infer-dev/.container/workspace/.cache` so rebuilds are fast.

3. **Container boot-time installer (optional, env-gated)**:
   - Add `/pei-from-host/stage-2/custom/install-sglang-offline.sh`:
     - Extract bundle into a stable Pixi project dir under the workspace, e.g. `/hard/volume/workspace/sglang-pixi-offline`.
     - Patch channels to local-only (`channels = ["./channel"]`) and re-lock to ensure runtime is offline.
     - Run `pixi install --frozen` + `pixi run verify`.
     - Write `.installed-from.json` with sha256 and settings (idempotency).

4. **SGLang server runner (TOML -> processes)**:
   - Add `/pei-from-host/stage-2/custom/check-and-run-sglang.sh`:
     - Parse TOML config and generate one launch command per enabled instance.
     - For each instance:
       - set `CUDA_VISIBLE_DEVICES` based on `gpu_ids`
       - run `pixi run ... python -m sglang.launch_server ...` (SGLang’s default port is `30000`; align container port with that for fewer surprises)
       - (Optional) support SGLang’s native YAML config by passing `--config <yaml>`; our TOML config can either map to CLI flags or generate YAML.
       - log to `/tmp/sglang-server-<name>.log` (or configured path)

5. **Wire into infer-dev stage-2 entrypoint**:
   - `infer-dev-entry.sh`:
     - always expose helpers under `/soft/app/sglang/`
     - optionally run install on boot when `AUTO_INFER_SGLANG_BUNDLE_ON_BOOT=1|true`
     - optionally start server(s) when `AUTO_INFER_SGLANG_ON_BOOT=1|true` and config is provided

6. **Models**:
   - Prefer host-mounted model directories under `/llm-models/...` (no downloading by default).
   - Optional (separate, env-gated) “download on boot” helper can be added later (HF/ModelScope), writing into `/hard/volume/workspace/llm-models/`.

### 2.2 Sequence diagram (steady-state usage)

```mermaid
sequenceDiagram
  participant Dev as Dev (host)
  participant Host as Host scripts
  participant Docker as Docker/Compose
  participant Entry as infer-dev-entry.sh
  participant Installer as install-sglang-offline.sh
  participant Runner as check-and-run-sglang.sh
  participant S as sglang.launch_server
  participant Client as OpenAI client/curl

  Dev->>Host: build-sglang-bundle.sh
  Host-->>Dev: sglang-offline-bundle.tar (workspace)

  Dev->>Docker: docker compose run/up stage-2 (+mount bundle +env vars)
  Docker->>Entry: container start

  alt AUTO_INFER_SGLANG_BUNDLE_ON_BOOT=true
    Entry->>Installer: extract + pixi install/verify
    Installer-->>Entry: /hard/volume/workspace/sglang-pixi-offline ready
  end

  alt AUTO_INFER_SGLANG_ON_BOOT=true and config provided
    Entry->>Runner: parse TOML + launch instances
    Runner->>S: pixi run python -m sglang.launch_server ...
  else
    Entry-->>Dev: no auto serve; helpers available
  end

  Dev->>Client: request http://127.0.0.1:<HOST_PORT_SGLANG>/v1/chat/completions
  Client->>S: OpenAI-compatible API call
  S-->>Client: response
```

## 3. Files to Modify or Add

- **`dockers/infer-dev/installation/stage-2/utilities/sglang-pixi-template/pixi.toml`**: Pixi template (no `.pixi/`) with pinned Torch/SGLang/FlashInfer/Transformers and `pypi-options` for wheel indexes.
- **`dockers/infer-dev/installation/stage-2/utilities/sglang-pixi-template/pixi.lock`**: Lock used by `pixi-pack` bundling.
- **`dockers/infer-dev/host-scripts/build-sglang-bundle.sh`**: Host builder for `sglang-offline-bundle.tar` (cache + retries; mirrors support).
- **`dockers/infer-dev/installation/stage-2/custom/install-sglang-offline.sh`**: In-container offline install into workspace, idempotent via sha256 marker.
- **`dockers/infer-dev/installation/stage-2/custom/check-and-run-sglang.sh`**: TOML runner that launches one/many SGLang servers via Pixi.
- **`dockers/infer-dev/installation/stage-2/custom/infer-dev-entry.sh`**: Add `/soft/app/sglang/*` helper symlinks and env-gated boot hooks.
- **`dockers/infer-dev/model-configs/sglang-*.toml`**: Example configs (e.g., `sglang-glm-4.7-tp8.toml`, `sglang-glm-4.7-flash-tp8.toml`).
- **`dockers/infer-dev/user_config.persist.yml`** / **`dockers/infer-dev/user_config.yml`**: Add `HOST_PORT_SGLANG` mapping (e.g. `11982:30000`) and optional model mounts for GLM-4.7 weights.
- **`dockers/infer-dev/README.md`**: Document env vars, install modes, ports, and example `curl` invocations.
- **`context/design/contract/def-sglang-config-toml.md`** (new): Document TOML schema and behavior.
- **`context/design/contract/sglang-config-toml.schema.json`** (optional): JSON schema for validation tooling.

## 4. TODOs (Implementation Steps)

- [ ] **Confirm latest SGLang install constraints** Check SGLang docs for recommended Torch version and FlashInfer wheel matrix for CUDA 12.6; decide pinned versions for `pixi.toml`.
- [ ] **Decide bundling strategy** Validate `pixi-pack` can pack required PyPI wheels for SGLang dependencies; if any dependency is sdist-only, decide between (a) pinning to a wheel-providing version, (b) enabling `--ignore-pypi-non-wheel`, or (c) adding an explicit “build from source” fallback.
- [ ] **Create SGLang Pixi template** Add `installation/stage-2/utilities/sglang-pixi-template/` with `pixi.toml`, `pixi.lock`, and a `verify` task (imports + CUDA check).
- [ ] **Implement host bundle builder** Add `dockers/infer-dev/host-scripts/build-sglang-bundle.sh`:
  - [ ] Use a temp working dir so the template stays free of `.pixi/`.
  - [ ] Add retries + optional `--rattler-config` mirroring like the vLLM builder.
  - [ ] Default caches into `dockers/infer-dev/.container/workspace/.cache/`.
- [ ] **Implement in-container offline installer** Add `install-sglang-offline.sh`:
  - [ ] Env vars: `AUTO_INFER_SGLANG_BUNDLE_PATH`, `AUTO_INFER_SGLANG_BUNDLE_SHA256`, `AUTO_INFER_SGLANG_PIXI_PROJECT_DIR`, `AUTO_INFER_SGLANG_PIXI_ENVIRONMENT`, `AUTO_INFER_SGLANG_PIXI_TEMPLATE_DIR`.
  - [ ] Extract bundle, patch `channels = ["./channel"]`, re-lock, install, run verify, write marker JSON.
- [ ] **Implement TOML runner** Add `check-and-run-sglang.sh`:
  - [ ] Parse TOML into per-instance server args.
  - [ ] Support `[master]` enable + project dir + environment.
  - [ ] Support per-instance: `host`, `port`, `model_path`, `served_model_name`, `tp_size`, `reasoning_parser`, `tool_call_parser`, `trust_remote_code`, `mem_fraction_static`, etc.
  - [ ] Consider supporting SGLang’s native `--config <yaml>` by allowing a raw YAML file per instance, or generating YAML from TOML to reduce CLI flag churn.
  - [ ] Support `gpu_ids` -> `CUDA_VISIBLE_DEVICES`.
- [ ] **Wire entrypoint hooks** Update `infer-dev-entry.sh`:
  - [ ] Create `/soft/app/sglang/install-sglang-offline.sh` + `/soft/app/sglang/check-and-run-sglang.sh` symlinks.
  - [ ] Add env gates:
    - [ ] `AUTO_INFER_SGLANG_BUNDLE_ON_BOOT=1|true` triggers install if bundle path is set.
    - [ ] `AUTO_INFER_SGLANG_ON_BOOT=1|true` triggers server start only when config is set.
- [ ] **Add example configs** Add `dockers/infer-dev/model-configs/sglang-*.toml` for GLM-4.7 (and/or GLM-4.7-Flash), including `glm45` + `glm47` parsers.
- [ ] **Expose ports and mounts** Update `user_config.persist.yml` to add a stable SGLang port mapping (e.g. host `11982` → container `30000`) and document the expected model mount layout.
- [ ] **Document workflow** Update `dockers/infer-dev/README.md` with:
  - [ ] Boot install + auto-serve example (compose + env vars + mounts).
  - [ ] Manual install + manual serve example (`docker exec` + `/soft/app/sglang/...`).
  - [ ] Troubleshooting section (FlashInfer backend, CUDA_HOME, wheel compatibility).
- [ ] **Validation checklist** Add a short manual smoke-test checklist:
  - [ ] `pixi run verify` succeeds in the installed project dir.
  - [ ] SGLang server starts and responds to `/v1/models` and `/v1/chat/completions`.
  - [ ] GLM-4.7 tool calling works with `--tool-call-parser glm47` and thinking parsing works with `--reasoning-parser glm45`.
