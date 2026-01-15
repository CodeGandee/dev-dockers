#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[llama-cpp-pkg] $*"
}

die() {
  echo "[llama-cpp-pkg] ERROR: $*" >&2
  exit 2
}

PKG_SRC="${AUTO_INFER_LLAMA_CPP_PKG_PATH:-}"
if [[ -z "$PKG_SRC" ]]; then
  log "AUTO_INFER_LLAMA_CPP_PKG_PATH not set; skipping."
  exit 0
fi

if [[ ! -f "$PKG_SRC" ]]; then
  die "Package not found: $PKG_SRC"
fi

PKG_BASENAME="$(basename -- "$PKG_SRC")"
case "$PKG_BASENAME" in
  *.tar|*.tar.gz|*.tgz|*.zip) ;;
  *)
    die "Unsupported package extension: $PKG_BASENAME (supported: .tar, .tar.gz, .tgz, .zip)"
    ;;
esac

CACHE_DIR="/soft/app/cache"
INSTALL_DIR="/soft/app/llama-cpp"

mkdir -p "$CACHE_DIR"

PKG_DST="$CACHE_DIR/$PKG_BASENAME"
if [[ -f "$PKG_DST" ]]; then
  log "Cache hit: $PKG_DST (skip copy)"
else
  log "Copying package to cache:"
  log "  src: $PKG_SRC"
  log "  dst: $PKG_DST"
  cp -f "$PKG_SRC" "$PKG_DST"
fi

PKG_SHA256="$(python3 - "$PKG_DST" <<'PY'
import hashlib
import sys
from pathlib import Path

p = Path(sys.argv[1])
h = hashlib.sha256()
with p.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
)"

log "Package sha256: $PKG_SHA256"

META_FILE="$INSTALL_DIR/.installed-from.json"
if [[ -f "$META_FILE" ]]; then
  if python3 - "$META_FILE" "$PKG_BASENAME" "$PKG_SHA256" <<'PY'
import json
import sys
from pathlib import Path

meta = json.loads(Path(sys.argv[1]).read_text("utf-8"))
want_name = sys.argv[2]
want_sha = sys.argv[3]
sys.exit(0 if meta.get("archive_name") == want_name and meta.get("sha256") == want_sha else 1)
PY
  then
    log "Already installed from $PKG_BASENAME ($PKG_SHA256); skipping extraction."
    exit 0
  fi
fi

log "Installing llama.cpp package into: $INSTALL_DIR"

TMP_EXTRACT_DIR="$(mktemp -d "$CACHE_DIR/.extract-llama-cpp.XXXXXX")"
log "Extracting to temp dir: $TMP_EXTRACT_DIR"

python3 - "$PKG_DST" "$TMP_EXTRACT_DIR" <<'PY'
import os
import sys
import tarfile
import zipfile
from pathlib import Path

archive_path = Path(sys.argv[1])
dest_dir = Path(sys.argv[2])

def safe_path(base: Path, target: Path) -> Path:
    resolved = (base / target).resolve()
    if not str(resolved).startswith(str(base.resolve()) + os.sep):
        raise RuntimeError(f"path traversal detected: {target}")
    return resolved

def extract_tar(path: Path, dest: Path) -> None:
    mode = "r:*"
    with tarfile.open(path, mode) as tf:
        for member in tf.getmembers():
            if member.name in ("", ".", ".."):
                continue
            out_path = safe_path(dest, Path(member.name))
            if member.isdir():
                out_path.mkdir(parents=True, exist_ok=True)
                continue
            out_path.parent.mkdir(parents=True, exist_ok=True)
            f = tf.extractfile(member)
            if f is None:
                continue
            with f, out_path.open("wb") as out:
                out.write(f.read())
            # Preserve executable bit best-effort
            if member.mode is not None and (member.mode & 0o111):
                out_path.chmod(out_path.stat().st_mode | 0o111)

def extract_zip(path: Path, dest: Path) -> None:
    with zipfile.ZipFile(path) as zf:
        for member in zf.infolist():
            name = member.filename
            if name in ("", ".", ".."):
                continue
            out_path = safe_path(dest, Path(name))
            if name.endswith("/"):
                out_path.mkdir(parents=True, exist_ok=True)
                continue
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, out_path.open("wb") as out:
                out.write(src.read())
            # Preserve executable bit best-effort (ZipInfo.external_attr stores mode in high 16 bits)
            mode = (member.external_attr >> 16) & 0o777
            if mode & 0o111:
                out_path.chmod(out_path.stat().st_mode | 0o111)

dest_dir.mkdir(parents=True, exist_ok=True)
if archive_path.name.endswith(".zip"):
    extract_zip(archive_path, dest_dir)
else:
    extract_tar(archive_path, dest_dir)
PY

# Determine package root:
# - Prefer $TMP_EXTRACT_DIR if it contains bin/
# - Otherwise accept a single top-level directory that contains bin/
PKG_ROOT="$TMP_EXTRACT_DIR"
if [[ ! -d "$PKG_ROOT/bin" ]]; then
  mapfile -t top_entries < <(find "$TMP_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%p\n')
  if [[ ${#top_entries[@]} -eq 1 && -d "${top_entries[0]}/bin" ]]; then
    PKG_ROOT="${top_entries[0]}"
  fi
fi

if [[ ! -d "$PKG_ROOT/bin" ]]; then
  rm -rf "$TMP_EXTRACT_DIR"
  die "Invalid package layout: expected bin/ at archive root (or a single top-level dir containing bin/)."
fi

if [[ ! -x "$PKG_ROOT/bin/llama-server" ]]; then
  rm -rf "$TMP_EXTRACT_DIR"
  die "Invalid package: missing executable bin/llama-server."
fi

if ! compgen -G "$PKG_ROOT"/README* >/dev/null; then
  log "Warning: package root has no README* file (expected by convention)."
fi

if ! compgen -G "$PKG_ROOT"/bin/*.so* >/dev/null; then
  log "Warning: package bin/ has no *.so* files (expected by convention)."
fi

TMP_INSTALL_DIR="$CACHE_DIR/.llama-cpp-install.$$"
rm -rf "$TMP_INSTALL_DIR"

log "Preparing install dir: $TMP_INSTALL_DIR"
if [[ "$PKG_ROOT" == "$TMP_EXTRACT_DIR" ]]; then
  mv "$TMP_EXTRACT_DIR" "$TMP_INSTALL_DIR"
else
  mv "$PKG_ROOT" "$TMP_INSTALL_DIR"
  rm -rf "$TMP_EXTRACT_DIR"
fi

# Atomically replace the install dir.
BACKUP_DIR=""
if [[ -e "$INSTALL_DIR" ]]; then
  BACKUP_DIR="$CACHE_DIR/.llama-cpp-prev.$$"
  log "Replacing existing install: $INSTALL_DIR -> $BACKUP_DIR"
  rm -rf "$BACKUP_DIR"
  mv "$INSTALL_DIR" "$BACKUP_DIR"
fi

log "Activating new install: $TMP_INSTALL_DIR -> $INSTALL_DIR"
mv "$TMP_INSTALL_DIR" "$INSTALL_DIR"

python3 - "$META_FILE" "$PKG_BASENAME" "$PKG_SHA256" <<'PY'
import json
import sys
import time
from pathlib import Path

meta_file = Path(sys.argv[1])
meta_file.parent.mkdir(parents=True, exist_ok=True)
meta = {
    "archive_name": sys.argv[2],
    "sha256": sys.argv[3],
    "installed_at_unix": int(time.time()),
}
meta_file.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

log "Installed."
log "  llama-server: $INSTALL_DIR/bin/llama-server"
log "  cached archive: $PKG_DST"

if [[ -n "$BACKUP_DIR" ]]; then
  log "Removing previous install backup: $BACKUP_DIR"
  rm -rf "$BACKUP_DIR"
fi

