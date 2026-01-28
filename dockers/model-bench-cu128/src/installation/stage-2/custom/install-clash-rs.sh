#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

STRICT="${PEI_STRICT_CLASH_RS:-0}"

die_or_skip() {
  echo "Warning: clash-rs install failed: $*" >&2
  echo "  Set PEI_STRICT_CLASH_RS=1 to fail the build on this error." >&2
  if [[ "${STRICT}" == "1" ]]; then
    exit 1
  fi
  exit 0
}

# Important: don't create real directories under /soft/app during build.
# PeiDocker links /soft/app -> /hard/{image|volume}/app at runtime, and will refuse to
# replace an existing directory. Install into the hard "image" path instead.
dest_dir="${PEI_PATH_HARD:-/hard}/${PEI_PREFIX_IMAGE:-image}/${PEI_PREFIX_APPS:-app}/clash"
mkdir -p "${dest_dir}"

arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64) arch_hint="amd64" ;;
  aarch64|arm64) arch_hint="arm64" ;;
  *)
    echo "Unsupported arch: ${arch}" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}" 2>/dev/null || true; }
trap cleanup EXIT

api_url="https://api.github.com/repos/Watfaq/clash-rs/releases/latest"
json_path="${tmp_dir}/release.json"
curl -fsSL "${api_url}" -o "${json_path}" || die_or_skip "failed to fetch ${api_url}"

python3 - "${json_path}" "${tmp_dir}/url.txt" "${arch_hint}" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
arch_hint = sys.argv[3]

data = json.loads(json_path.read_text())
assets = data.get("assets") or []

def score(url: str) -> int:
    u = url.lower()
    s = 0
    if "linux" in u:
        s += 10
    if arch_hint in u:
        s += 10
    if any(x in u for x in ("x86_64", "amd64")) and arch_hint == "amd64":
        s += 5
    if any(x in u for x in ("aarch64", "arm64")) and arch_hint == "arm64":
        s += 5
    if u.endswith((".tar.gz", ".tgz", ".zip")):
        s += 2
    if any(x in u for x in (".sha256", ".sha256sum", ".sig")):
        s -= 100
    return s

candidates = []
for a in assets:
    url = a.get("browser_download_url")
    if not url:
        continue
    candidates.append((score(url), url))

candidates.sort(reverse=True)
best = candidates[0][1] if candidates else ""
out_path.write_text(best)
PY

download_url="$(cat "${tmp_dir}/url.txt")"
if [[ -z "${download_url}" ]]; then
  die_or_skip "failed to find a suitable clash-rs asset in latest release"
fi

archive_path="${tmp_dir}/asset"
curl -fsSL "${download_url}" -o "${archive_path}" || die_or_skip "failed to download ${download_url}"

bin_path=""
case "${download_url}" in
  *.tar.gz|*.tgz)
    tar -xzf "${archive_path}" -C "${tmp_dir}"
    bin_path="$(find "${tmp_dir}" -maxdepth 3 -type f -name 'clash-rs' -o -name 'clash' | head -n 1 || true)"
    ;;
  *.zip)
    unzip -q "${archive_path}" -d "${tmp_dir}"
    bin_path="$(find "${tmp_dir}" -maxdepth 3 -type f -name 'clash-rs' -o -name 'clash' | head -n 1 || true)"
    ;;
  *)
    # Assume direct binary
    bin_path="${archive_path}"
    ;;
esac

if [[ -z "${bin_path}" || ! -f "${bin_path}" ]]; then
  die_or_skip "failed to locate clash-rs binary after download"
fi

install_path="${dest_dir}/clash-rs"
install -m 0755 "${bin_path}" "${install_path}"
echo "Installed clash-rs to ${install_path}"
