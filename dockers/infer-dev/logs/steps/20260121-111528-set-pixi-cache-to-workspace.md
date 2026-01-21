# Step log: set Pixi/Rattler cache to workspace

## Goal

Move Pixi/Rattler cache writes off of `/home/<user>/.cache` and onto the host-mounted workspace cache directory:

- Container path: `/hard/volume/workspace/.cache` (same mount as `dockers/infer-dev/.container/workspace/.cache` on the host)

## Repo changes (for future builds)

- Set global env vars in stage-2 profile setup:
  - Updated `dockers/infer-dev/installation/stage-2/internals/setup-profile-d.sh` to write:
    - `XDG_CACHE_HOME=/hard/volume/workspace/.cache`
    - `RATTLER_CACHE_DIR=/hard/volume/workspace/.cache/rattler/cache`
    into `/etc/environment`.
- Ensure cache directories exist at runtime:
  - Updated `dockers/infer-dev/installation/stage-2/custom/infer-dev-entry.sh` to create
    `/hard/volume/workspace/.cache/rattler/cache` and make it writable.

## Applied to the running container

In the currently running compose container `infer-dev-stage-2-1`:

- Created cache dirs:
  - `mkdir -p /hard/volume/workspace/.cache/rattler/cache`
- Wrote `/etc/profile.d/infer-dev-cache.sh`:
  - exports `XDG_CACHE_HOME` and `RATTLER_CACHE_DIR`
- Updated `/etc/environment` to include/override:
  - `XDG_CACHE_HOME=/hard/volume/workspace/.cache`
  - `RATTLER_CACHE_DIR=/hard/volume/workspace/.cache/rattler/cache`

## Validation

Confirmed as user `me`:

- `pixi info` now reports:
  - `Cache dir: /hard/volume/workspace/.cache/rattler/cache`

