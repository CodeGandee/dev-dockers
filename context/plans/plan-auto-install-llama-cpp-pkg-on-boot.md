# Plan: Auto-install llama.cpp package on container boot

## HEADER

- **Purpose**: Add an opt-in mechanism to install a prebuilt `llama.cpp` binary bundle into `infer-dev` at container start, so serving can use a custom or downloaded build without rebuilding the image.
- **Status**: Draft
- **Date**: 2026-01-15
- **Dependencies**:
  - `dockers/infer-dev/installation/stage-2/custom/infer-dev-entry.sh`
  - `dockers/infer-dev/installation/stage-2/custom/check-and-run-llama-cpp.sh`
  - `context/design/contract/def-llama-cpp-config-toml.md`
  - `context/design/contract/llama-cpp-config-toml.schema.json`
  - `dockers/infer-dev/README.md`
  - `README.md`
- **Target**: Contributors maintaining `dockers/infer-dev` and users running `llama.cpp` servers inside the container.

---

## 1. Purpose and Outcome

Implement an **on-boot installer** triggered by:
- `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1|true` and
- `AUTO_INFER_LLAMA_CPP_PKG_PATH=/path/to/pkg.(tar|tar.gz|tgz|zip)`

The installer:

- Copies a provided archive (`.tar`, `.tar.gz`/`.tgz`, `.zip`) into `/soft/app/cache` and keeps it there.
- Extracts the archive into `/soft/app/llama-cpp` so binaries are available at a stable path.
- Is idempotent: if the archive already exists in `/soft/app/cache`, skip copying; if `/soft/app/llama-cpp` is already installed from the same archive, skip extraction.
- Prints clear, step-by-step progress messages.

Success looks like:

- Users can start a container with `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1` and `AUTO_INFER_LLAMA_CPP_PKG_PATH=/some/mounted/llama-cpp-build.tar.gz`, then run `/soft/app/llama-cpp/bin/llama-server` or configure `llama_cpp_path` accordingly.
- Auto-serving remains gated by `AUTO_INFER_LLAMA_CPP_ON_BOOT`, independent from package installation.

## 2. Implementation Approach

### 2.1 High-level flow

1. On container boot, `infer-dev-entry.sh` checks `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT` and `AUTO_INFER_LLAMA_CPP_PKG_PATH`.
2. If enabled, run an installer script (new) that:
   1. Validates the archive exists and has a supported extension.
   2. Ensures `/soft/app/cache` exists.
   3. Copies the archive to `/soft/app/cache/<basename>` unless it already exists there.
   4. Extracts into a temp directory, validates it contains `/bin`, then atomically replaces `/soft/app/llama-cpp`.
   5. Writes an install marker (e.g., `/soft/app/llama-cpp/.installed-from.json`) recording basename + sha256.
3. `infer-dev-entry.sh` then:
   - Ensures a “manual start” symlink exists: `/soft/app/llama-cpp/check-and-run-llama-cpp.sh` (already present via current logic).
   - If `AUTO_INFER_LLAMA_CPP_ON_BOOT=1|true`, launches instances from `AUTO_INFER_LLAMA_CPP_CONFIG` (existing behavior).

### 2.2 Sequence diagram (steady-state usage)

```mermaid
sequenceDiagram
  participant Dev as Dev
  participant Docker as Docker
  participant Entry as infer-dev entry
  participant Installer as pkg installer
  participant Server as llama-server

  Dev->>Docker: docker run -e AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1 -e AUTO_INFER_LLAMA_CPP_PKG_PATH=/mnt/pkg.tgz
  Docker->>Entry: start container (/entrypoint.sh -> infer-dev-entry.sh)
  Entry->>Installer: install pkg if env set
  Installer-->>Entry: /soft/app/cache/<pkg> + /soft/app/llama-cpp ready
  alt AUTO_INFER_LLAMA_CPP_ON_BOOT=true
    Entry->>Server: start llama-server from TOML config
  else AUTO_INFER_LLAMA_CPP_ON_BOOT unset/false
    Entry-->>Dev: no auto-start; user can run helper later
  end
  Dev->>Docker: docker exec ... /soft/app/llama-cpp/check-and-run-llama-cpp.sh
  Docker->>Server: starts llama-server (manual)
```

## 3. Files to Modify or Add

- **dockers/infer-dev/installation/stage-2/custom/infer-dev-entry.sh**: Invoke package installer early on boot; keep auto-start gating unchanged.
- **dockers/infer-dev/installation/stage-2/custom/install-llama-cpp-pkg.sh** (new): Copy + extract archive into `/soft/app/llama-cpp` with logs and idempotency.
- **dockers/infer-dev/README.md**: Document `AUTO_INFER_LLAMA_CPP_PKG_PATH` and the expected package layout.
- **README.md**: Add a short “use a prebuilt llama.cpp package” note under the inference section.
- (Optional) **context/design/contract/def-llama-cpp-config-toml.md**: Mention the recommended `llama_cpp_path` when using `/soft/app/llama-cpp/bin/llama-server`.

## 4. TODOs (Implementation Steps)

- [ ] **Define package layout contract** Document that the archive root contains `README*` and `bin/` with `llama-server` plus required `.so` files (e.g., `libggml-*.so`, `libllama.so`).
- [ ] **Implement installer script** Add `installation/stage-2/custom/install-llama-cpp-pkg.sh` that:
  - [ ] Validates `AUTO_INFER_LLAMA_CPP_PKG_PATH` exists and is a regular file.
  - [ ] Copies to `/soft/app/cache/<basename>` if not already present.
  - [ ] Computes sha256 of the cached archive and stores install metadata.
  - [ ] Extracts via an embedded Python snippet using `tarfile`/`zipfile` (avoids relying on `unzip` being installed).
  - [ ] Extracts to a temp dir then atomically replaces `/soft/app/llama-cpp` to avoid partial installs.
  - [ ] Validates extracted tree contains `bin/llama-server` before “activating” it.
- [ ] **Wire into entry** Update `infer-dev-entry.sh` to call the installer when `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1|true` and `AUTO_INFER_LLAMA_CPP_PKG_PATH` is set (and log when skipping).
- [ ] **Keep serving gating** Ensure `AUTO_INFER_LLAMA_CPP_CONFIG` never triggers serving by itself; serving still requires `AUTO_INFER_LLAMA_CPP_ON_BOOT=1|true`.
- [ ] **Symlink convenience entrypoint** Ensure `/soft/app/llama-cpp/check-and-run-llama-cpp.sh` points to the script that reads TOML and launches servers.
- [ ] **Update docs** Add usage examples:
  - [ ] “Boot install only”: install pkg on start, no server auto-start.
  - [ ] “Boot install + auto-start”: set `AUTO_INFER_LLAMA_CPP_GET_PKG_ON_BOOT=1`, `AUTO_INFER_LLAMA_CPP_PKG_PATH`, and `AUTO_INFER_LLAMA_CPP_ON_BOOT=1` + config.
- [ ] **Manual verification** Add a short checklist to validate:
  - [ ] First boot copies + extracts; second boot reuses cache and skips extraction when unchanged.
  - [ ] `llama_cpp_path=/soft/app/llama-cpp/bin/llama-server` works with `check-and-run-llama-cpp.sh`.
