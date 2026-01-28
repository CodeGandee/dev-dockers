# PeiDocker Project Usage Guide

This project was generated/configured by PeiDocker.

## Project Structure

*   `src/user_config.yml`: **Main configuration file.** Edit this to define your image, SSH users, scripts, etc.
*   `src/docker-compose.yml`: Generated file.
    *   **Note**: You **CAN** modify this file manually to add advanced Docker features not supported by PeiDocker.
    *   **Warning**: Running `./pei-configure.sh` will **OVERWRITE** this file. If you make manual changes, ensure you back them up or be prepared to re-apply them after re-configuration.
*   `src/installation/`: Directory copied into the container at `/pei-from-host`.
    *   `stage-1/`: System layer scripts (APT, SSH, Proxy).
    *   `stage-2/`: Application layer scripts (Pixi, Conda, Custom).
    *   `stage-2/custom/`: Place your custom setup scripts here.

## How to Configure

1.  Edit `src/user_config.yml`.
2.  Run configuration command to regenerate artifacts:
    ```bash
    ./pei-configure.sh
    ```
    *   Add `--with-merged` to generate standalone build scripts (`src/build-merged.sh`).

## How to Build and Run

### Option A: Docker Compose (Standard)

*   **Build**:
    ```bash
    docker compose -f src/docker-compose.yml build stage-2
    ```
*   **Run**:
    ```bash
    # Starts stage-2 service by default (stage-1 is excluded)
    docker compose -f src/docker-compose.yml up
    
    # Detached mode
    docker compose -f src/docker-compose.yml up -d
    ```
*   **SSH**:
    Connect to the port defined in `src/user_config.yml` (default host port: 2222).
    ```bash
    ssh <user>@localhost -p 2222
    ```

### Option B: Merged Build (Standalone)

Useful if you want a single `docker build` command or don't want to use Compose.

1.  Ensure you ran `./pei-configure.sh --with-merged`.
2.  **Build**:
    ```bash
    ./src/build-merged.sh
    ```
3.  **Run**:
    ```bash
    ./src/run-merged.sh
    
    # Run with interactive shell
    ./src/run-merged.sh --shell
    ```

## Scripts & Customization

*   **Build Hooks**: Add scripts to `custom.on_build` in `src/user_config.yml`.
*   **Runtime Hooks**: Add scripts to `custom.on_first_run`, `on_every_run`, or `on_user_login`.
*   **System Scripts**: PeiDocker provides built-in scripts in `src/installation/stage-*/system/` (e.g., for installing Pixi, UV, Conda). Reference them in your config.

## Troubleshooting

*   **Rebuild**: If you change `src/user_config.yml`, always run `./pei-configure.sh` again.
*   **Stage 1 vs Stage 2**:
    *   `Stage 1`: Base system (Ubuntu + CUDA + SSH + APT). Changes here invalidate the whole cache.
    *   `Stage 2`: Application layer. Optimized for frequent changes.
