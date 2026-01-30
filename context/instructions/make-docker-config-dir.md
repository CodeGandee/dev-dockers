you are tasked to create a docker compose environment directory that follows the same layout/pattern as `dockers/model-bench-cu128` (from the companion `dev-dockers` repo).

the output is a *directory structure* plus a small set of tracked config files and helper scripts that make it easy to:
- keep the environment root clean
- generate docker artifacts via `pei-docker-cli configure`
- keep `.env` untracked but documented via `env.example`
- keep host/container mappings configurable via `HOST_PORT_*` / `CONTAINER_PORT_*` and `HOST_VOLUME_*` / `CONTAINER_VOLUME_*`

## expected directory tree

create the directory (commonly `dockers/<env-name>/`) with at least:

```text
dockers/<env-name>/
  README.md
  env.example
  pei-configure.sh
  docs/
    README.md
  memo/
    README.md
  issues/
  src/
    README.md
    user_config.yml
    user_config.persist.yml
    compose-template.yml
    reference_config.yml
    installation/
      stage-1/
        custom/
      stage-2/
        custom/
```

notes:
- `docs/`, `memo/`, `issues/` are optional, but match `model-bench-cu128` and help keep operational notes out of `README.md`.
- `.env` is not tracked; `env.example` must be tracked.
- generated artifacts should live under `src/` (not at the env root).

## what each file should contain

### `README.md` (env root)

must include:
- env purpose (1-2 lines)
- quick start commands:
  - `./pei-configure.sh` (or `./pei-configure.sh --with-merged` if you support merged builds)
  - build command (`docker compose -f src/docker-compose.yml build ...` or `./src/build-merged.sh ...`)
  - run command (`docker compose -f src/docker-compose.yml up -d ...`)
- a note that `.env` is not tracked and should be copied from `env.example`
- pointers to `memo/` or `docs/` if they exist

### `env.example`

must list all host-overridable settings used by `src/user_config.yml` (and by the generated compose), especially:
- `HOST_PORT_*` used for ssh/http services (example: `HOST_PORT_SSH`, `HOST_PORT_PROXY`)
- any `HOST_VOLUME_*` paths if you mount host directories

keep this file minimal and safe (no secrets).

### `compose-template.yml`

store this file at `src/compose-template.yml`.

this is the input template for `pei-docker-cli configure` (omegaconf-style). keep it as close as possible to the PeiDocker project template, but:
- ensure it supports stage-1 and stage-2
- include `extra_hosts: ["host.docker.internal:host-gateway"]` if the config relies on host proxy
- do not hardcode host paths/ports; route through config variables that can be controlled from `.env` (via `src/user_config.yml`)

### `reference_config.yml`

store this file at `src/reference_config.yml`.

provide a fully annotated reference configuration (like `dockers/model-bench-cu128/src/reference_config.yml`) that users can consult.
- include comments for ssh key options and proxy/apt settings
- do not include real keys, tokens, or private host paths

### `src/user_config.yml` and `src/user_config.persist.yml`

these are the user-facing PeiDocker configs used by `pei-configure.sh`.
- `src/user_config.yml` should use env-var fallbacks for host-specific values, for example:
  - `host_port: ${HOST_PORT_SSH:-2222}`
  - `port: ${HOST_PORT_PROXY:-7890}`
- keep `src/user_config.persist.yml` identical to `src/user_config.yml` unless you have a clear reason to diverge.
- keep paths relative to the PeiDocker installation directory; in this layout the installation directory is tracked at `src/installation/`
- keep all custom logic in `src/installation/stage-*/custom/` and invoke scripts via `custom.on_build` / `custom.on_first_run` / etc

### `src/installation/`

create/keep these folders:
- `src/installation/stage-1/custom/` and `src/installation/stage-2/custom/`
- add placeholder `README.md` files explaining where to put custom scripts

do not commit secrets (private keys, tokens). if generated files contain user-specific data, replace with safe placeholders before committing.

## `pei-configure.sh` requirements (important)

create `pei-configure.sh` similar to `dockers/model-bench-cu128/pei-configure.sh`:
- run `pixi run pei-docker-cli configure -p "<env-root>" -c "src/user_config.yml" ...`
- keep the env root clean:
  - keep `src/compose-template.yml` tracked, and create a *temporary symlink* at `<env-root>/compose-template.yml` during configure (PeiDocker expects this file at the project root)
  - ensure `installation/` at env root is a *temporary symlink* to `src/installation/` during configure
  - refuse to overwrite a real directory named `installation/` at env root
- move root-level generated artifacts into `src/` (if they exist), including:
  - `docker-compose.yml`, `stage-1.Dockerfile`, `stage-2.Dockerfile`
  - `merged.Dockerfile`, `merged.env`, `build-merged.sh`, `run-merged.sh` (when `--with-merged` is used)
  - `PEI-DOCKER-USAGE-GUIDE.md`
- patch generated paths so `src/docker-compose.yml` works when run from the env root:
  - build `context` should point to the env root (typically `..` if compose is in `src/`)
  - `dockerfile:` paths should point to `src/stage-*.Dockerfile`
  - any `./installation/...` references should become `./src/installation/...`
  - any `.container/` references should become `../.container/` (if present)

## validation checklist

after creating the directory:
- `cd dockers/<env-name> && ./pei-configure.sh --with-merged` succeeds (or without `--with-merged` if unsupported)
- `src/docker-compose.yml` exists and can be used from the env root:
  - `docker compose -f src/docker-compose.yml build stage-2`
  - `docker compose -f src/docker-compose.yml up -d stage-2`
- `env.example` matches the env vars used in `src/user_config.yml`
- `.env` is not committed
