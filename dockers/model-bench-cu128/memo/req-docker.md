# Docker Requirements: Model Benchmarking (CUDA 12.8)

**Goal:** Create a high-performance environment for benchmarking deep learning models (Inference & Training) on the latest CUDA 12.8 stack.

## 1. Base System
*   **Base Image:** `docker.1ms.run/nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04` (ID: `468c101db63b`).
*   **OS:** Ubuntu 24.04 (Noble Numbat).
*   **CUDA:** 12.8.1 (Devel with cuDNN).
*   **Python:** 3.11 or 3.12 (standardize on recent stable).

## 2. Software Packages Requirements
*   **Editors & Utilities:**
    *   `nano`, `micro` (CLI Editors).
    *   `mc` (Midnight Commander file manager).
    *   `tmux`, `curl`, `wget`, `git`, `git-lfs`, `unzip`.
    *   `qimgv` (Image viewer).
*   **OpenCV & GUI Support (for `cv2.imshow()`):**
    *   `libgl1-mesa-glx`, `libglib2.0-0` (Core GL and Glib).
    *   `libsm6`, `libxext6`, `libxrender1` (X11 client libraries).
    *   `x11-apps`, `xauth` (For X11 forwarding).
    *   `libopencv-dev` (Optional, if native build is needed).
*   **Runtime & Package Managers (Installed at build time via PeiDocker, for user `peid`):**
    *   **Pixi:** `stage-2/system/pixi/install-pixi.bash --user peid --pypi-repo tuna --conda-repo tuna` (Environment management with Tuna mirrors).
        *   **Global Packages:** Also install at build time: `pixi global install jq yq nvitop btop helix gh` as user `peid`.
    *   **uv:** `stage-1/system/uv/install-uv.sh --user peid --pypi-repo tuna` (Fast Python package installer with Tuna mirror).
    *   **Node.js Stack:**
        *   **NVM:** `su - peid -c "bash /pei-from-host/stage-2/system/nodejs/install-nvm.sh --with-cn-mirror"` (Install NVM with npmmirror registry).
        *   **Node.js:** `stage-2/system/nodejs/install-nodejs.sh --user peid` (Install Node.js LTS using NVM).
        *   **Login-shell availability:** ensure NVM init is added to `~/.profile` (not only `~/.bashrc`) and a default alias exists so `runuser -l peid -c 'bash -lc \"node --version\"'` works immediately after build.
    *   **Bun:** `stage-2/system/bun/install-bun.sh --user peid --npm-repo https://registry.npmmirror.com` (Fast JS runtime with npmmirror).
        *   **Global Packages:** Also install at build time as user `peid`:
            *   `bun add -g tavily-mcp@latest`
            *   `bun add -g @upstash/context7-mcp@latest @google/gemini-cli@latest`
    *   **Claude Code:** `stage-2/system/claude-code/install-claude-code.sh --user peid` (AI Coding Assistant).
    *   **Codex CLI:** `stage-2/system/codex-cli/install-codex-cli.sh --user peid` (AI-powered coding agent for terminal).
    *   **Custom Scripts:**
        *   Any operations not covered by the standard `stage-{1,2}` system scripts (e.g., `pixi global install`, `bun add -g`) MUST be implemented in custom scripts and invoked via `user_config.yml` `custom.on_build` (not `on_first_run`).
    *   **External Tools:**
        *   **Clash-RS:** At build time, download the latest release executable from `https://github.com/Watfaq/clash-rs/releases`.
            *   Install into `/hard/image/app/clash/` during image build.
            *   It will be available at runtime under `/soft/app/clash/` (PeiDocker creates `/soft/app -> /hard/.../app` as a symlink on container start).

## 4. Environment & Connectivity
*   **APT Mirror:** Use Tsinghua Tuna (`tuna`) as the Ubuntu APT source during build.
    *   **Configuration (`user_config.yml`):**
        ```yaml
        apt:
          repo_source: 'tuna'
          keep_repo_after_build: true
        ```
*   **Proxy Support:** Automatically inherit host proxy settings (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`) during the build process if available in the environment.
    *   **IMPORTANT:** Proxy settings MUST NOT be persisted in the final image (i.e., do not bake them into `/etc/environment` or shell profiles).
    *   **Configuration (`user_config.yml`):**
        ```yaml
        proxy:
          address: host.docker.internal
          port: ${HOST_PORT_PROXY:-7890}
          # Use host proxy for build, but remove it afterwards
          enable_globally: true
          remove_after_build: true
        ```
*   **SSH Server:** Standard `pei-docker` setup for remote VSCode/PyCharm attachment.
*   **User Configuration:**
    *   **User:** `peid`
    *   **Password:** `123456`
    *   **UID:** `3100`
    *   **GID:** `1100`
    *   **SSH Access:** Automatically add the host's public key to `peid`'s `authorized_keys` using PeiDocker's standard mechanism (via `user_config.yml` `ssh` section).
    *   **Configuration (`user_config.yml`):**
        ```yaml
        ssh:
          users:
            peid:
              password: '123456'
              uid: 3100
              gid: 1100
              # Path to public key on host to inject into container
              pubkey_file: '~'
        ```
*   **Package Management:** `pixi` (preferred) or `uv` for reproducible environments.
*   **Git:** Pre-configured.
