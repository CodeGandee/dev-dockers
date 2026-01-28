# Plan: Build `ig-model-bench:cu128` via `pei-docker-cli`

This plan implements the requirements in `dockers/model-bench-cu128/memo/req-docker.md` using PeiDocker (`pei-docker-cli`), and produces the final image tag:

- `ig-model-bench:cu128`

## TODO (Progress Tracker)

### Scaffolding

- [x] Create PeiDocker project scaffold under `dockers/model-bench-cu128/src/` (including `src/installation/`)
- [x] Add `dockers/model-bench-cu128/src/user_config.persist.yml`
- [x] Add `dockers/model-bench-cu128/src/user_config.yml` (generated from persist config)
- [x] Add `dockers/model-bench-cu128/pei-configure.sh` wrapper (optional but recommended, like `dockers/infer-dev/pei-configure.sh`)

### Config (PeiDocker)

- [x] Set stage-1 base image to `docker.1ms.run/nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`
- [x] Set stage-2 output image to `ig-model-bench:cu128`
- [x] Configure GPU usage for both stages (`device.type: gpu`)
- [x] Configure SSH user `peid` (`password=123456`, `uid=3100`, `gid=1100`, inject host pubkey)
- [x] Configure APT mirror to Tsinghua Tuna (`apt.repo_source: 'tuna'`)
- [x] Configure build-time proxy (inherit host), and ensure it is removed after build (do not bake into `/etc/environment`)

### Custom scripts (Requirements)

- [x] Stage-1 on-build: install apt packages (editors/utils + X11/OpenCV GUI deps)
- [x] Stage-1 on-build: install `uv` as user `peid` (with Tuna PyPI mirror)
- [x] Stage-2 on-build: install `pixi`, `nodejs` (via NVM), `bun`, `claude-code`, `codex-cli` as user `peid`
- [x] Stage-2 on-build: run custom “post-install” commands:
  - `pixi global install jq yq nvitop btop helix gh`
  - `bun add -g tavily-mcp@latest`
  - `bun add -g @upstash/context7-mcp@latest @google/gemini-cli@latest`
- [x] Stage-2 on-build: download latest `clash-rs` to `/soft/app/clash/` (implemented by writing into `/hard/image/app/...` so `/soft/app` can be symlinked at runtime)
- [x] Ensure `node` works for `peid` in login shells (NVM init in `~/.profile` + a valid `nvm alias default`)

### Generate / Build / Run

- [x] Run configure (`./pei-configure.sh --with-merged` or `pixi run pei-docker-cli configure ...`)
- [x] Build image (compose or merged) and confirm final tag is `ig-model-bench:cu128`
- [x] Run container and validate GPU + Python + tooling
- [x] Validate proxy was not baked into final image

## 1) Project layout (recommended)

Follow the repo pattern used by `dockers/infer-dev/`:

- Keep PeiDocker generated artifacts under `dockers/model-bench-cu128/src/`:
  - `src/user_config.yml`
  - `src/user_config.persist.yml`
  - `src/docker-compose.yml` (generated)
  - `src/stage-1.Dockerfile` (generated)
  - `src/stage-2.Dockerfile` (generated)
  - `src/merged.Dockerfile`, `src/build-merged.sh`, `src/run-merged.sh` (generated via `--with-merged`)
  - `src/installation/` (tracked scripts/assets copied into image)

## 2) Configuration mapping (`user_config.persist.yml`)

### Stage 1 (base system)

- Base image:
  - `stage_1.image.base: docker.1ms.run/nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`
- Output tag (helper tag):
  - `stage_1.image.output: ig-model-bench:cu128-stage-1` (or similar)
- GPU:
  - `stage_1.device.type: gpu`
- SSH:
  - `stage_1.ssh.enable: true`
  - `stage_1.ssh.port: 22`
  - `stage_1.ssh.host_port: ${HOST_PORT_SSH:-2222}`
  - `stage_1.ssh.users.peid.password: '123456'`
  - `stage_1.ssh.users.peid.uid: 3100`
  - `stage_1.ssh.users.peid.gid: 1100`
  - `stage_1.ssh.users.peid.pubkey_file: '~'` (inject host public key)
- Proxy (build-time only; must not persist):
  - `stage_1.proxy.address: host.docker.internal`
  - `stage_1.proxy.port: ${HOST_PORT_PROXY:-7890}`
  - `stage_1.proxy.enable_globally: true`
  - `stage_1.proxy.remove_after_build: true`
  - `stage_1.apt.use_proxy: false` (enable only if your apt downloads require proxy)
  - `stage_1.apt.keep_proxy_after_build: false`
- APT mirror (required):
  - `stage_1.apt.repo_source: 'tuna'`
  - `stage_1.apt.keep_repo_after_build: true`

### Stage 2 (dev/runtime layer)

- Output tag (final image):
  - `stage_2.image.output: ig-model-bench:cu128`
- GPU:
  - `stage_2.device.type: gpu`
- Storage (choose based on desired persistence; example for “dev”):
  - `stage_2.storage.workspace.type: host`
  - `stage_2.storage.workspace.host_path: .container/workspace`
  - (optional) also persist home to keep shell history / VSCode server:
    - `stage_2.mount.home_peid.type: auto-volume`
    - `stage_2.mount.home_peid.dst_path: /home/peid`

## 3) Custom scripts (what/where)

Per repo guidance: put all custom logic in `installation/stage-*/custom/` and invoke from `custom.*` in config.

### Stage 1 scripts

1. `src/installation/stage-1/custom/install-apt-packages.sh` (on-build)
   - Install required packages:
     - Editors & utilities: `nano`, `micro`, `mc`, `tmux`, `curl`, `wget`, `git`, `git-lfs`, `unzip`
     - GUI/vision: `qimgv`, `libgl1-mesa-glx`, `libglib2.0-0`, `libsm6`, `libxext6`, `libxrender1`, `x11-apps`, `xauth`, `libopencv-dev`
       - Note: on Ubuntu 24.04, `libgl1-mesa-glx` may be unavailable; fall back to `libgl1`.
     - Python base: `python3`, `python3-pip`, `python3-venv`
2. `src/installation/stage-1/custom/install-uv.sh` (on-build)
   - Calls `stage-1/system/uv/install-uv.sh --user peid --pypi-repo tuna`

### Stage 2 scripts

1. `src/installation/stage-2/custom/install-devtools.sh` (on-build)
   - Calls the standard system installers:
     - `stage-2/system/pixi/install-pixi.bash --user peid --pypi-repo tuna --conda-repo tuna`
     - `su - peid -c "bash /pei-from-host/stage-2/system/nodejs/install-nvm.sh --with-cn-mirror"` (NVM + npm mirror)
     - `stage-2/system/nodejs/install-nodejs.sh --user peid` (Node.js LTS via NVM)
     - `stage-2/system/bun/install-bun.sh --user peid --npm-repo https://registry.npmmirror.com`
     - `stage-2/system/claude-code/install-claude-code.sh --user peid`
     - `stage-2/system/codex-cli/install-codex-cli.sh --user peid`
   - Then runs the required “not covered by system scripts” commands as user `peid`:
     - `pixi global install jq yq nvitop btop helix gh`
     - `bun add -g tavily-mcp@latest`
     - `bun add -g @upstash/context7-mcp@latest @google/gemini-cli@latest`
   - Ensure `node` is available in login shells by relying on the Node.js system scripts:
     - `install-nvm.sh` appends NVM init to `~/.profile`
     - `install-nodejs.sh` sets `nvm alias default ...` after install
   - Note: Bun may report “Blocked postinstalls”; if a tool misbehaves, run `bun pm -g untrusted` as `peid`.
2. `src/installation/stage-2/custom/install-clash-rs.sh` (on-build)
   - Downloads latest `clash-rs` release binary and places it at `/soft/app/clash/`
     - Implementation note: write into `/hard/image/app/clash/` during build, so PeiDocker can create the `/soft/app -> /hard/.../app` symlink on container start.

## 4) Configure / Build / Run commands

### Configure (generate dockerfiles/compose)

From repo root:

```bash
cd dockers/model-bench-cu128
cp src/user_config.persist.yml src/user_config.yml

# Option A (recommended): wrapper that keeps generated artifacts in src/
./pei-configure.sh --with-merged

# Option B: direct
pixi run pei-docker-cli configure -p dockers/model-bench-cu128 --with-merged -c src/user_config.yml
```

### Build

Compose:

```bash
docker compose -f src/docker-compose.yml build stage-2 --progress=plain
```

Merged (ensures final tag):

```bash
./src/build-merged.sh -o ig-model-bench:cu128 -- --progress=plain
```

### Run

```bash
docker compose -f src/docker-compose.yml up -d stage-2
```

## 5) Validation checklist (inside container)

- GPU works: `nvidia-smi`
- Python present: `python3 --version`
- Core tooling (available immediately after build):
  - `pixi --version`, `uv --version`, `node --version`, `bun --version`
  - For Node specifically (NVM): verify in a login shell for `peid`, e.g. `runuser -l peid -c 'bash -lc "node --version"'`
  - Bun globals: `tavily-mcp --help`, `context7-mcp --help`, `gemini --help`
  - clash-rs binary: `ls -la /soft/app/clash/clash-rs` (or equivalently `/hard/image/app/clash/clash-rs`)
- Proxy not baked into image:
  - `/etc/environment` should NOT contain `http_proxy`, `https_proxy`, `HTTP_PROXY`, `HTTPS_PROXY`
- APT mirror in effect:
  - `/etc/apt/sources.list` or `/etc/apt/sources.list.d/ubuntu.sources` should reference the `tuna` mirror
- OpenCV GUI deps exist:
  - Verify imports: `python3 -c "import cv2; print(cv2.__version__)"`
  - For `cv2.imshow()`, validate via X11 forwarding workflow (SSH `-X` / `-Y` depending on host setup)
