# Issue: `install-nvm.sh` doesn’t make `node` available in login shells (non-interactive)

## Summary

PeiDocker’s Node.js setup installs NVM by appending NVM init to `~/.bashrc` only. On Ubuntu, `~/.bashrc` typically exits early for **non-interactive** shells, and login shells may rely on `~/.profile` / `~/.bash_profile`. Result: **Node is installed under `~/.nvm/...` but `node` is not on `PATH`** in common “login shell + command” flows.

This showed up when validating `node` for the `peid` user inside the `ig-model-bench:cu128` image.

## Repro (inside container)

1. Install NVM + Node:
   - `su - peid -c "bash /pei-from-host/stage-2/system/nodejs/install-nvm.sh --with-cn-mirror"`
   - `stage-2/system/nodejs/install-nodejs.sh --user peid`
2. Run a login-shell command:
   - `runuser -l peid -c 'bash -lc "node --version"'`

## Expected

`node --version` works for `peid` in a login shell.

## Actual

`node` is not found unless the user runs an interactive shell that sources NVM properly, or manually sources `~/.nvm/nvm.sh`.

## Why it happens

- `install-nvm.sh` writes NVM init lines to `~/.bashrc`.
- Ubuntu’s default `~/.bashrc` typically contains an early return for non-interactive shells, so the NVM init is skipped in `bash -lc` scenarios.

## Suggested upstream fix

In addition to `~/.bashrc`, also write NVM init to a login-shell startup file:

- Preferred: append to `~/.profile`:
  - `export NVM_DIR="$HOME/.nvm"`
  - `[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"`
  - optionally `nvm use --silent default >/dev/null 2>&1 || true`
- Optional: set a default alias after node install:
  - `nvm alias default "$(nvm current)"`

## Status / Local fix applied (2026-01-28)

Applied an upstream-style fix in the PeiDocker template scripts and synced it into this env:

- Patched PeiDocker templates:
  - `extern/tracked/PeiDocker/src/pei_docker/project_files/installation/stage-2/system/nodejs/install-nvm.sh`
  - `extern/tracked/PeiDocker/src/pei_docker/project_files/installation/stage-2/system/nodejs/install-nodejs.sh`
  - `extern/tracked/PeiDocker/src/pei_docker/project_files/installation/stage-2/system/nodejs/install-nvm-nodejs.sh`
- Synced the same changes into this env’s pinned scripts:
  - `dockers/model-bench-cu128/src/installation/stage-2/system/nodejs/install-nvm.sh`
  - `dockers/model-bench-cu128/src/installation/stage-2/system/nodejs/install-nodejs.sh`
  - `dockers/model-bench-cu128/src/installation/stage-2/system/nodejs/install-nvm-nodejs.sh`

With this fix, `runuser -l peid -c 'bash -lc \"node --version\"'` works immediately after build without extra custom `~/.profile` hacks.
