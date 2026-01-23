# Test plan: Validate the offline-first SGLang tutorial (no-egress + warm cache)

This test plan validates `dockers/infer-dev/docs/tutorial/offline-sglang-on-infer-dev/README.md` **in this repo**, while simulating an **offline machine** by **blocking container internet egress**.

In addition to functional correctness, this plan requires **evidence**:

- Create a **Markdown report per step** with command output and key logs.
- Maintain a **Docker resource ledger** (networks/containers/images/volumes created) so cleanup is deterministic.

Key constraints for this plan:

1) **Offline simulation**: the container must not be able to reach the public internet during the “offline” phase.
2) **Warm cache**: prepare once, reuse later. We avoid deleting:
   - host Pixi/Rattler cache used to build the bundle
   - the built SGLang offline bundle
   - the unpacked runtime env under the workspace mount

---

## 0) Reporting + resource ledger (required)

### 0.1 Create a test run folder

Store evidence under `dockers/infer-dev/logs/tests/` so it can be reviewed (and optionally committed) later.

From repo root:

```bash
export REPO_ROOT="$(git rev-parse --show-toplevel)"
export TEST_RUN_ID="$(date +%Y%m%d-%H%M%S)-offline-sglang-no-egress"
export TEST_RUN_DIR="${REPO_ROOT}/dockers/infer-dev/logs/tests/${TEST_RUN_ID}"
mkdir -p "$TEST_RUN_DIR"

export LEDGER_FILE="$TEST_RUN_DIR/RESOURCES.md"
cat > "$LEDGER_FILE" <<'MD'
# Docker resources ledger

## Created/used by this test run

> Update this file during the run. Include resource name, ID (when available), and cleanup command.

| Type | Name | ID (optional) | Created by step | Cleanup |
|---|---|---|---|---|
MD
```

### 0.2 Helper: capture command output into a step report

Use this pattern for every step:

```bash
export STEP_FILE="$TEST_RUN_DIR/NN-step-name.md"

{
  echo "# Step NN: <title>"
  echo
  echo "## When"
  date -Is
  echo
  echo "## Commands + output"
  echo
  echo '```bash'
  echo "<paste commands here>"
  echo '```'
  echo
} > "$STEP_FILE"

# Then run the commands and append output:
<command> 2>&1 | tee -a "$STEP_FILE"
```

### 0.3 Baseline snapshot (do this first)

Create `00-baseline.md` with enough info to prove the run happened on a specific machine + Docker state.

```bash
STEP_FILE="$TEST_RUN_DIR/00-baseline.md"
{
  echo "# Step 00: Baseline snapshot"
  echo
  echo "## When"; date -Is
  echo
  echo "## Host info"
  echo '```'
  uname -a
  echo '```'
  echo
  echo "## Docker versions"
  echo '```'
  docker version
  docker compose version
  echo '```'
  echo
  echo "## GPU visible on host"
  echo '```'
  nvidia-smi -L || true
  echo '```'
  echo
  echo "## Existing resources (for diffing later)"
  echo '```'
  docker ps -a
  docker network ls
  docker volume ls
  docker image ls infer-dev:stage-1 infer-dev:stage-2 || true
  echo '```'
} > "$STEP_FILE"
```

## A. One-time preparation (online)

> Run once. Re-run only if you change the SGLang template, bundle, or images.

### A1) Build `infer-dev` images

Create report: `01-build-images.md`

```bash
cd dockers/infer-dev

# If you edited user_config.yml, regenerate docker-compose.yml / merged.env first:
pei-docker-cli configure --with-merged

# Build from scratch
docker compose --profile build-helper build stage-1
docker compose build stage-2

# Evidence (copy into the report):
docker image ls infer-dev:stage-1 infer-dev:stage-2
docker image inspect infer-dev:stage-1 infer-dev:stage-2 --format '{{.RepoTags}} {{.Id}} {{.Created}} {{.Size}}'
```

Update `RESOURCES.md` for the images you built/validated:

- Type: `image`
- Name: `infer-dev:stage-1`
- Cleanup: `docker image rm -f infer-dev:stage-1` (only when you really want to delete it)

- Type: `image`
- Name: `infer-dev:stage-2`
- Cleanup: `docker image rm -f infer-dev:stage-2` (only when you really want to delete it)

### A2) Prepare (warm) host cache for SGLang bundle build

Create report: `02-build-sglang-bundle.md`

This fills persistent caches under `dockers/infer-dev/.container/workspace/.cache/`:

- `.../.cache/rattler/cache` (conda downloads / repodata)
- `.../.cache/pixi-pack` (pixi-pack cache)

Build the **self-extracting** bundle (recommended for offline container installs):

```bash
./dockers/infer-dev/host-scripts/build-sglang-bundle.sh --create-executable \
  -o dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh
```

Record sha256 (optional; used for idempotency checks):

```bash
sha256sum dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh
ls -lh dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh
```

### A3) Prepare a local model directory (online)

Create report: `03-model-prep.md`

For this test, pick a model that you already have downloaded on the host, or download one now.

Offline requirement: the model path must already exist **on the host** and be mounted into the container.

For **this test plan**, use the repo’s model reference:

- Host model reference: `models/qwen2-vl-7b/source-data`
- Expected target model: **Qwen2-VL-7B-Instruct**

Bootstrap the model reference (creates/refreshes the `source-data` symlink):

```bash
cd "$REPO_ROOT"
bash models/qwen2-vl-7b/bootstrap.sh

export HOST_MODEL_DIR="${REPO_ROOT}/models/qwen2-vl-7b/source-data"

# Evidence:
ls -la "${REPO_ROOT}/models/qwen2-vl-7b" | sed -n '1,50p'
ls -la "$HOST_MODEL_DIR" | sed -n '1,50p'
```

If you need a smaller/faster model for repeated testing, prefer using a smaller text-only model and update the config in step A4 accordingly.

### A4) Create a test-only SGLang TOML config for Qwen2-VL-7B

Create report: `04-create-sglang-config.md`

This plan uses a config stored inside the test run folder and mounted into the container.

Create `${TEST_RUN_DIR}/sglang-qwen2-vl-7b.toml`:

```bash
cat > "${TEST_RUN_DIR}/sglang-qwen2-vl-7b.toml" <<'TOML'
[master]
enable = true
project_dir = "/hard/volume/workspace/sglang-pixi-offline"

[instance.control]
log_dir = "/tmp"
background = true
gpu_ids = "0"

[instance.server]
host = "0.0.0.0"
port = 30000
trust_remote_code = true

[instance.qwen2_vl_7b.server]
model_path = "/llm-models/Qwen2-VL-7B-Instruct"
served_model_name = "qwen2-vl-7b"
tp_size = 1
TOML

# Evidence:
sed -n '1,200p' "${TEST_RUN_DIR}/sglang-qwen2-vl-7b.toml"
```

---

## B. Offline simulation setup (no container internet)

We simulate “offline machine” by running the container on a Docker bridge network with NAT (masquerade) disabled.

This blocks typical outbound internet access while still allowing:

- host → container port mappings (`-p ...` / compose ports)
- container ↔ container on the same Docker bridge network

### B1) Create the “no-egress” network

Create report: `10-create-no-egress-network.md`

```bash
docker network inspect infer-dev-no-egress >/dev/null 2>&1 || \
  docker network create --driver bridge \
    --opt com.docker.network.bridge.enable_ip_masquerade=false \
    infer-dev-no-egress

# Evidence:
docker network inspect infer-dev-no-egress
```

Update `RESOURCES.md` with the created network and cleanup command:

- Type: `network`
- Name: `infer-dev-no-egress`
- Cleanup: `docker network rm infer-dev-no-egress`

### B2) Create a temporary compose override that uses this external network

Create report: `11-compose-offline-override.md`

Create a throwaway override file (keep it around for reuse):

```bash
cat > dockers/infer-dev/.container/workspace/docker-compose.offline.override.yml <<'YAML'
services:
  stage-2:
    networks:
      - offline

networks:
  offline:
    external: true
    name: infer-dev-no-egress
YAML

# Evidence:
cat dockers/infer-dev/.container/workspace/docker-compose.offline.override.yml
```

---

## C. Test case 1: Offline auto-install + auto-serve on boot

Goal: confirm the tutorial’s intended “offline runtime” workflow works end-to-end.

### C1) Start the container (offline network) with auto-install + auto-serve enabled

Create report: `20-offline-auto-install-auto-serve.md`

From `dockers/infer-dev/`:

```bash
cd dockers/infer-dev

docker rm -f infer-sglang-offline >/dev/null 2>&1 || true

docker compose \
  -f docker-compose.yml \
  -f .container/workspace/docker-compose.offline.override.yml \
  run -d --service-ports --name infer-sglang-offline \
  -v "${TEST_RUN_DIR}:/test-run:ro" \
  -v "${HOST_MODEL_DIR}:/llm-models/Qwen2-VL-7B-Instruct:ro" \
  -e AUTO_INFER_SGLANG_BUNDLE_ON_BOOT=1 \
  -e AUTO_INFER_SGLANG_BUNDLE_PATH=/hard/volume/workspace/sglang-offline-bundle.sh \
  -e AUTO_INFER_SGLANG_ON_BOOT=1 \
  -e AUTO_INFER_SGLANG_CONFIG=/test-run/sglang-qwen2-vl-7b.toml \
  stage-2 sleep infinity

# Evidence:
docker ps --filter name=infer-sglang-offline --no-trunc
docker inspect infer-sglang-offline --format '{{.Id}} {{.Name}} {{.Created}}'
docker inspect infer-sglang-offline --format '{{json .NetworkSettings.Networks}}' | sed 's/},{/},\\n{/g'
```

Update `RESOURCES.md` with the created container:

- Type: `container`
- Name: `infer-sglang-offline`
- Cleanup: `docker rm -f infer-sglang-offline`

### C2) Assert the container has no internet access

Create report: `21-offline-no-egress-check.md`

This should fail (timeout or connect error). Use `--noproxy '*'` to avoid host proxy env vars interfering:

```bash
docker exec infer-sglang-offline bash -lc \
  "curl --noproxy '*' -fsS --max-time 5 https://pypi.org/simple/ >/dev/null && echo UNEXPECTED_OK || echo OK_NO_EGRESS"
```

Also capture a DNS/route hint (optional but useful in reports):

```bash
docker exec infer-sglang-offline bash -lc 'route -n || true'
docker exec infer-sglang-offline bash -lc 'cat /etc/resolv.conf || true'
```

### C3) Assert SGLang was installed into the workspace

Create report: `22-offline-install-artifacts.md`

Expected install output location:

- `/hard/volume/workspace/sglang-pixi-offline/`

Check:

```bash
docker exec infer-sglang-offline bash -lc \
  "ls -la /hard/volume/workspace/sglang-pixi-offline && ls -la /hard/volume/workspace/sglang-pixi-offline/env/bin/python"

# Marker / provenance:
docker exec infer-sglang-offline bash -lc \
  "cat /hard/volume/workspace/sglang-pixi-offline/.installed-from.json || true"
```

### C4) Assert SGLang is serving (host-side)

Create report: `23-offline-serving-smoke.md`

This repo maps:

- host `11982` → container `30000`

#### C4.1 Models endpoint returns valid JSON

```bash
curl --noproxy '*' -fsS --max-time 10 http://127.0.0.1:11982/v1/models \
  | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
assert isinstance(data, dict)
assert "data" in data, data.keys()
assert isinstance(data["data"], list)
print("ok: /v1/models returned", len(data["data"]), "model entries")
PY
```

#### C4.2 Chat completion returns a valid result (not just “server started”)

This must return a JSON payload with `choices[0].message.content` (or equivalent) populated.

```bash
curl --noproxy '*' -fsS --max-time 120 http://127.0.0.1:11982/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2-vl-7b","messages":[{"role":"user","content":"Say hi and return a short answer."}],"max_tokens":32}' \
  | python3 - <<'PY'
import json, sys
resp = json.load(sys.stdin)
if "error" in resp:
    raise SystemExit(f"error field present: {resp['error']}")
choices = resp.get("choices")
assert isinstance(choices, list) and len(choices) >= 1, resp.keys()
msg = choices[0].get("message") or {}
content = msg.get("content")
assert content is not None and str(content).strip(), "empty content"
print("ok: chat completion content:", str(content)[:200])
PY
```

### C5) Check logs (if needed)

Create report: `24-offline-server-logs.md` (when you need it)

Default log file naming is based on instance name in the TOML:

```bash
docker exec infer-sglang-offline bash -lc 'ls -la /tmp/sglang-server-*.log && tail -n 200 /tmp/sglang-server-*.log'
```

---

## D. Test case 2: Offline restart (warm cache + idempotent install)

Goal: verify the “warm cache” workflow for repeated testing/debugging:

- do **not** rebuild the bundle
- do **not** delete the workspace
- installer should detect existing install and exit quickly

### D1) Stop and remove only the container

Create report: `30-offline-restart-clean-container.md`

```bash
docker rm -f infer-sglang-offline
```

### D2) Start again with the same command as C1

Create report: `31-offline-restart-auto-serve.md`

Re-run the C1 command.

Expected:

- install script prints “Already installed …” (idempotency via marker file + sha256 when available)
- server starts without any network access

Repeat checks:

- C2 (no egress)
- C4 (serving)

---

## E. Test case 3: Offline boot without SGLang, then manual install + manual serve

Goal: validate the tutorial’s “no auto-start” path and manual helpers.

### E1) Start container offline WITHOUT SGLang env vars

Create report: `40-offline-no-auto-start.md`

```bash
cd dockers/infer-dev

docker rm -f infer-dev-offline >/dev/null 2>&1 || true

docker compose \
  -f docker-compose.yml \
  -f .container/workspace/docker-compose.offline.override.yml \
  run -d --service-ports --name infer-dev-offline \
  -v "${TEST_RUN_DIR}:/test-run:ro" \
  -v "${HOST_MODEL_DIR}:/llm-models/Qwen2-VL-7B-Instruct:ro" \
  stage-2 sleep infinity

# Evidence:
docker ps --filter name=infer-dev-offline --no-trunc
```

Update `RESOURCES.md` with the created container:

- Type: `container`
- Name: `infer-dev-offline`
- Cleanup: `docker rm -f infer-dev-offline`

### E2) Assert SGLang is NOT serving initially

Create report: `41-offline-not-serving-initially.md`

Expect failure (connection refused / timeout):

```bash
curl --noproxy '*' -fsS --max-time 3 http://127.0.0.1:11982/v1/models && echo UNEXPECTED_OK || echo OK_NOT_SERVING
```

### E3) Manually install from the offline bundle

Create report: `42-offline-manual-install.md`

```bash
docker exec -it \
  -e AUTO_INFER_SGLANG_BUNDLE_PATH=/hard/volume/workspace/sglang-offline-bundle.sh \
  infer-dev-offline \
  /soft/app/sglang/install-sglang-offline.sh
```

### E4) Manually start serving from TOML config

Create report: `43-offline-manual-serve.md`

```bash
docker exec -it \
  -e AUTO_INFER_SGLANG_CONFIG=/test-run/sglang-qwen2-vl-7b.toml \
  infer-dev-offline \
  /soft/app/sglang/check-and-run-sglang.sh
```

Then verify:

```bash
curl --noproxy '*' -fsS --max-time 10 http://127.0.0.1:11982/v1/models \
  | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
assert isinstance(data, dict)
assert isinstance(data.get("data"), list)
print("ok: /v1/models returned", len(data["data"]), "model entries")
PY

curl --noproxy '*' -fsS --max-time 120 http://127.0.0.1:11982/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2-vl-7b","messages":[{"role":"user","content":"Say hi and return a short answer."}],"max_tokens":32}' \
  | python3 - <<'PY'
import json, sys
resp = json.load(sys.stdin)
if "error" in resp:
    raise SystemExit(f"error field present: {resp['error']}")
choices = resp.get("choices")
assert isinstance(choices, list) and len(choices) >= 1, resp.keys()
msg = choices[0].get("message") or {}
content = msg.get("content")
assert content is not None and str(content).strip(), "empty content"
print("ok: chat completion content:", str(content)[:200])
PY
```

---

## F. “Warm cache” rules (do/don’t)

### Keep (to accelerate repeat tests)

- `dockers/infer-dev/.container/workspace/.cache/` (host cache + container cache)
- `dockers/infer-dev/.container/workspace/sglang-offline-bundle.sh` (offline bundle)
- `dockers/infer-dev/.container/workspace/sglang-pixi-offline/` (unpacked runtime env)

### Delete only when you want a clean “first install” simulation

- Delete the unpacked env (forces reinstall from the bundle, still offline):

```bash
rm -rf dockers/infer-dev/.container/workspace/sglang-pixi-offline
```

Do **not** delete the cache directories unless you explicitly want to re-download everything online.

---

## G. Cleanup (and final evidence)

Create report: `90-cleanup.md`

Before cleanup, snapshot the resources you created (paste into the report):

```bash
docker ps -a --filter name=infer-sglang-offline --filter name=infer-dev-offline
docker network ls | grep -n 'infer-dev-no-egress' || true
```

```bash
docker rm -f infer-sglang-offline infer-dev-offline >/dev/null 2>&1 || true
docker network rm infer-dev-no-egress >/dev/null 2>&1 || true
```

If you want to keep the network for future debugging, skip removing it.

After cleanup, capture a final snapshot (paste into the report):

```bash
docker ps -a --filter name=infer-sglang-offline --filter name=infer-dev-offline
docker network ls | grep -n 'infer-dev-no-egress' || true
```

---

## H. What to review (for “this really happened” verification)

In the test run folder (`$TEST_RUN_DIR`), reviewers should be able to see:

- `00-baseline.md` with timestamps + Docker/GPU context
- Reports showing:
  - the network was created with `enable_ip_masquerade=false`
  - container egress checks fail during “offline” steps
  - the SGLang env exists under `/hard/volume/workspace/sglang-pixi-offline/`
  - `/v1/models` and `/v1/chat/completions` succeed on host `127.0.0.1:11982`
- `RESOURCES.md` listing everything created and how to delete it
