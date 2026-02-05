# How to Create a Self-Hosted Conda-Forge Subset Repository with Pixi

This guide explains how to use **Pixi** to create a local Conda channel containing a specific subset of packages and their full dependency tree. This allows for offline installations or hosting a private mirror.

## Overview

1.  **Define**: Use a temporary Pixi project to define the desired packages.
2.  **Resolve**: Let Pixi resolve the dependency tree and generate a `pixi.lock` file.
3.  **Fetch**: Use a script to parse `pixi.lock` and download the exact package artifacts.
4.  **Index**: Use `rattler-index` (fast, Rust-based) to generate the channel metadata.

## Prerequisites

-   [Pixi](https://prefix.dev/) installed.

## Step-by-Step Guide

### 1. Setup a "Builder" Project

Create a temporary project to define the packages you want to mirror.

```bash
mkdir my-mirror-builder
cd my-mirror-builder
pixi init
```

Add the packages you want in your mirror (e.g., `pandas`, `pytorch`), plus the tools we need (`rattler-index` and `pyyaml`).

```bash
# Add your target packages
pixi add pandas scikit-learn

# Add build tools (needed for the script and indexing)
pixi add rattler-index pyyaml requests
```

This generates a `pixi.lock` file containing the exact URLs and metadata for every dependency.

### 2. Create the Mirror Script

Save the following Python script as `build_mirror.py` in the same directory. This script reads the lock file and downloads the artifacts.

```python
import yaml
import os
import requests
from pathlib import Path
from urllib.parse import urlparse

def build_mirror(lock_file="pixi.lock", output_dir="local-channel"):
    with open(lock_file, "r") as f:
        lock_data = yaml.safe_load(f)

    packages = lock_data.get("packages", [])
    if not packages:
        print("No packages found in lock file.")
        return

    print(f"Found {len(packages)} packages to process.")
    
    for pkg in packages:
        # We only care about conda packages (not pypi)
        if pkg.get("kind") == "pypi":
            print(f"Skipping PyPI package: {pkg['name']}")
            continue

        platform = pkg.get("platform") # e.g., 'linux-64' or 'noarch'
        url = pkg.get("url")
        
        if not platform or not url:
            continue

        # Create target directory
        target_dir = Path(output_dir) / platform
        target_dir.mkdir(parents=True, exist_ok=True)

        # Extract filename from URL
        filename = os.path.basename(urlparse(url).path)
        target_path = target_dir / filename

        if target_path.exists():
            print(f"Skipping {filename} (exists)")
            continue

        print(f"Downloading {filename} to {platform}/...")
        try:
            resp = requests.get(url, stream=True)
            resp.raise_for_status()
            with open(target_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
        except Exception as e:
            print(f"Failed to download {url}: {e}")

if __name__ == "__main__":
    build_mirror()
```

### 3. Run the Build

Execute the script using Pixi's python environment:

```bash
pixi run python build_mirror.py
```

This will create a `local-channel/` directory structured like:
```
local-channel/
├── linux-64/
│   ├── pandas-2.0.0-...conda
│   └── ...
└── noarch/
    └── ...
```

### 4. Index the Channel

Now use `rattler-index` to generate the `repodata.json` which makes this directory a valid Conda channel.

```bash
pixi run rattler-index local-channel
```

### 5. Usage

Your `local-channel` is now ready.

**Using with Pixi:**

In a generic project, you can now point to this channel. If it's on the filesystem:

`pixi.toml`:
```toml
[project]
name = "offline-project"
channels = ["file:///absolute/path/to/local-channel"]
platforms = ["linux-64"]

[dependencies]
pandas = "*"
```

**Using with Conda:**

```bash
conda create -n my-env -c file://$(pwd)/local-channel pandas --offline
```

## Advanced Tips

-   **Multi-Platform:** To mirror packages for other platforms (e.g., `osx-arm64`), you need to configure your builder project to include those platforms:
    ```bash
    # Edit pixi.toml manually to add other platforms
    # platforms = ["linux-64", "osx-arm64"]
    ```
    Then run `pixi install` (or `pixi lock`) to update the lock file before running the script.
-   **PyPI Packages:** The script above skips PyPI packages. Pixi handles PyPI/Conda mixing, but Conda channels only store Conda packages. For PyPI mirroring, you need a separate tool (like `pypi-mirror` or `bandersnatch`).

## Merging and Updating Channels

If you need to add more packages later (e.g., `scipy`), you don't need to "merge" metadata manually. The process is additive:

1.  **Download New Packages**: Use the same builder project (or a new one) to download the *new* set of packages into a temporary directory.
2.  **Copy Files**: Copy the package files (`.conda` or `.tar.bz2`) from the new batch into your existing `local-channel` directories (e.g., merge the `linux-64` folders).
3.  **Re-Index**: Run `rattler-index` on the *combined* `local-channel` folder. It will scan all files (old and new) and regenerate a fresh `repodata.json`.

```bash
# Example: After copying new files into local-channel/linux-64/
pixi run rattler-index local-channel
```

## Alternative: Pixi-Pack

If your goal is simply to **transport a single environment** to an offline machine (rather than hosting a reusable repository/channel), you should use [pixi-pack](https://github.com/Quantco/pixi-pack).

`pixi-pack` creates a compressed, single-file archive of your environment that can be unpacked on a target machine without internet access.

```bash
# Install pixi-pack
pixi global install pixi-pack

# Pack the current environment
pixi-pack
# Creates 'environment.tar' (or similar) containing all packages

# Unpack on target machine
./pixi-unpack environment.tar
```

## Resources

-   [Pixi Documentation](https://pixi.sh/)
-   [Rattler Index](https://github.com/conda-forge/rattler-index-feedstock)
