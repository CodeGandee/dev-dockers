# How to Move a Pixi Environment to Another Machine Offline

This guide explains how to transfer a Pixi project and its environment to another machine running the same operating system without requiring internet access on the target machine.

There are two primary methods:
1.  **Method 1: Direct Copy (Fast, Strict Constraints)** - Best when you can replicate the exact directory path.
2.  **Method 2: Pixi Pack (Flexible, Recommended)** - Best when directory paths might differ or for cleaner distribution.

---

## Method 1: Direct Copy (Same Path Requirement)

This method involves simply copying the project directory (including `.pixi`).

### The Constraint: Absolute Paths
> **The project must reside at the EXACT SAME ABSOLUTE PATH on the target machine.**

Executables in `.pixi/envs/default/bin/` (e.g., `pip`, `pytest`) contain "shebang" lines pointing to the absolute path of the python interpreter. If the path changes, scripts will fail with `bad interpreter`.

### Procedure

1.  **Identify Source Path**:
    ```bash
    pwd
    # Example: /data/projects/my-app
    ```

2.  **Prepare Target Machine**:
    Ensure the exact same directory structure exists.
    ```bash
    sudo mkdir -p /data/projects
    sudo chown $USER:$USER /data/projects
    ```

3.  **Copy Project**:
    Transfer the directory, **including the hidden `.pixi` folder**.
    ```bash
    rsync -avz my-app/ user@target:/data/projects/my-app/
    ```

4.  **Verify**:
    ```bash
    cd /data/projects/my-app
    pixi run pip --version
    ```

---

## Method 2: Pixi Pack (Flexible Path)

This method uses `pixi-pack` to bundle all dependencies. It allows `pixi install` to run offline on the target machine, regenerating shebangs for *any* directory path.

### Prerequisites
- **Source Machine**: Internet access, `pixi` installed.
- **Target Machine**: `pixi` installed (binary can be copied manually).

### Procedure

1.  **Install pixi-pack (Source)**:
    ```bash
    pixi global install pixi-pack
    ```

2.  **Create Dependency Pack (Source)**:
    Navigate to your project (where `pixi.toml` is) and pack dependencies.
    ```bash
    # Replace 'linux-64' with target platform if different.
    # Use --use-cache to avoid re-downloading packages across repeated pack builds.
    pixi-pack -p linux-64 --use-cache ~/.cache/pixi-pack -o offline-packages.tar /path/to/project-or-pixi.toml
    ```

3.  **Transfer and Extract (Target)**:
    Move `offline-packages.tar` and project files to the target. Extract the pack inside the project root.
    ```bash
    # Inside project root
    tar -xf offline-packages.tar
    # Creates a 'channel/' directory
    ```
    Note: `pixi-pack` writes a tar archive. If you’re unsure about the format, run `file offline-packages.tar`.

4.  **Configure Local Channel (Target)**:
    Edit `pixi.toml` to point to the local `channel` directory instead of remote ones (like `conda-forge`).

    ```toml
    [workspace]
    # channels = ["conda-forge"]  <-- Remove/Comment remote channels
    channels = ["./channel"]      <-- Add local channel path
    platforms = ["linux-64"]
    ```

5.  **Install Offline (Target)**:
    Run the standard install. Pixi will use the local packages to build the environment, correctly setting up paths for the new location.
    ```bash
    pixi install --frozen
    ```

### Notes

- Prefer keeping `pixi.toml` + `pixi.lock` with the project and using `pixi install --frozen` on the target.
- `pixi-pack` also supports `--create-executable` for a self-extracting bundle; see `pixi-pack --help` for details.
