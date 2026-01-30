#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ -z "${PEI_STAGE_DIR_2:-}" ]]; then
  echo "Error: PEI_STAGE_DIR_2 is not set" >&2
  exit 1
fi

run_as_user() {
  local user="$1"
  shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "${user}" -- "$@"
  else
    su - "${user}" -c "$*"
  fi
}

stage_dir="${PEI_STAGE_DIR_2}"

# Pixi (with tuna mirrors)
"${stage_dir}/system/pixi/install-pixi.bash" --user peid --conda-repo tuna --pypi-repo tuna

# Node.js (install nvm first, then nodejs)
run_as_user peid bash -lc "set -euo pipefail; '${stage_dir}/system/nodejs/install-nvm.sh' --with-cn-mirror"
"${stage_dir}/system/nodejs/install-nodejs.sh" --user peid

# Bun
"${stage_dir}/system/bun/install-bun.sh" --user peid --npm-repo https://registry.npmmirror.com

# Claude Code + Codex CLI
"${stage_dir}/system/claude-code/install-claude-code.sh" --user peid
"${stage_dir}/system/codex-cli/install-codex-cli.sh" --user peid

# Post-install global tools (must be custom per requirements)
peid_home="$(getent passwd peid | cut -d: -f6)"
pixi_bin="${peid_home}/.pixi/bin/pixi"
bun_bin="${peid_home}/.bun/bin/bun"
profile_path="${peid_home}/.profile"

ensure_line() {
  local file="$1"
  local line="$2"
  touch "${file}"
  if ! grep -qF -- "${line}" "${file}"; then
    printf '\n%s\n' "${line}" >> "${file}"
  fi
}

primary_group="$(id -gn peid 2>/dev/null || echo peid)"
chown "peid:${primary_group}" "${profile_path}" || true

if [[ ! -x "${pixi_bin}" ]]; then
  echo "Error: pixi not found at ${pixi_bin}" >&2
  exit 1
fi
if [[ ! -x "${bun_bin}" ]]; then
  echo "Error: bun not found at ${bun_bin}" >&2
  exit 1
fi

run_as_user peid "${pixi_bin}" global install jq yq nvitop btop helix gh
ensure_line "${profile_path}" 'export PATH="$HOME/.pixi/bin:$PATH"'
chown "peid:${primary_group}" "${profile_path}" || true

# Bun global installs (required for some Codex skills)
run_as_user peid "${bun_bin}" add -g tavily-mcp@latest

# Optional packages: may require npm credentials or registry access.
if ! run_as_user peid "${bun_bin}" add -g @upstash/context7-mcp@latest @google/gemini-cli@latest; then
  echo "Warning: bun global install failed (missing credentials or registry blocked?)." >&2
  echo "  Command: bun add -g @upstash/context7-mcp@latest @google/gemini-cli@latest" >&2
  echo "  Set PEI_STRICT_BUN_GLOBAL=1 to fail the build on this error." >&2
  if [[ "${PEI_STRICT_BUN_GLOBAL:-0}" == "1" ]]; then
    exit 1
  fi
fi

