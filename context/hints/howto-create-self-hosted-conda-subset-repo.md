# How to Create a Self-Hosted Conda-Forge Subset Repository

This guide explains how to create a local Conda channel that contains a specific subset of packages along with **all their dependencies**, ensuring they are fully installable offline or from a private server.

## Overview

The process involves:
1.  Resolving the full dependency tree for your desired packages.
2.  Downloading the exact artifacts (tarballs/conda packages) for the target platform(s).
3.  Organizing them into a standard Conda channel structure.
4.  Indexing the channel using `conda-index`.

## Prerequisites

-   `conda` installed.
-   `conda-index` installed (usually part of `conda-build` or installed standalone via `conda install conda-index`).
-   Python (for the helper script).

## Step-by-Step Guide

### 1. Resolve Dependencies and Generate URL List

Use `conda create --dry-run --json` to let Conda's solver identify every required package without installing anything. We will parse this output to get the download URLs and correct subdirectories (e.g., `linux-64`, `noarch`).

Save the following Python script as `fetch_deps.py`:

```python
import subprocess
import json
import os
import sys
from urllib.request import urlretrieve

def fetch_packages(packages, channel_dir="local-channel", channels=["conda-forge"]):
    # 1. Solve the environment to get the package list
    print(f"Solving dependencies for: {', '.join(packages)}...")
    cmd = [
        "conda", "create",
        "--name", "__dry_run_env__",
        "--dry-run",
        "--json"
    ]
    # Add channels
    for c in channels:
        cmd.extend(["-c", c])
    
    cmd.extend(packages)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print("Error solving environment:")
        print(e.stderr)
        sys.exit(1)

    if "actions" not in data or "LINK" not in data["actions"]:
        print("No packages to link. Check if they are already installed or the names are correct.")
        return

    links = data["actions"]["LINK"]
    print(f"Found {len(links)} packages to download.")

    # 2. Download packages
    for link in links:
        url = link["url"]
        subdir = link["subdir"]  # e.g., 'linux-64' or 'noarch'
        fn = link["fn"]          # e.g., 'package-1.0.tar.bz2'
        
        # Target directory: local-channel/<subdir>/
        target_dir = os.path.join(channel_dir, subdir)
        os.makedirs(target_dir, exist_ok=True)
        
        target_path = os.path.join(target_dir, fn)
        
        if os.path.exists(target_path):
            print(f"Skipping {fn} (already exists)")
            continue
            
        print(f"Downloading {fn} to {subdir}/...")
        try:
            urlretrieve(url, target_path)
        except Exception as e:
            print(f"Failed to download {url}: {e}")

if __name__ == "__main__":
    # usage: python fetch_deps.py <package1> <package2> ...
    if len(sys.argv) < 2:
        print("Usage: python fetch_deps.py <package_name> [package_name ...]")
        sys.exit(1)
        
    pkgs = sys.argv[1:]
    fetch_packages(pkgs)
```

### 2. Execute the Download

Run the script with your desired top-level packages.

```bash
# Example: Create a repo with pandas and scikit-learn
python fetch_deps.py pandas scikit-learn
```

This will create a directory `local-channel/` containing `linux-64/` and/or `noarch/` subdirectories with all necessary `.tar.bz2` or `.conda` files.

### 3. Index the Channel

Use `conda-index` to generate the `repodata.json` metadata required by Conda.

```bash
# Install conda-index if you haven't
conda install conda-index

# Index the directory
conda index local-channel/
```

### 4. Usage

You can now install packages from this local channel.

**Local Filesystem:**
```bash
conda create -n my-env -c file://$(pwd)/local-channel pandas scikit-learn --offline
```

**Web Server:**
If you serve the `local-channel` directory via Nginx/Apache/Python HTTP server:
```bash
# Serve (simple example)
cd local-channel && python -m http.server 8000

# Install
conda create -n my-env -c http://localhost:8000 pandas scikit-learn
```

## Tips

-   **Platform Specificity:** The `conda create` command solves for the *current* platform by default. To create a mirror for a different platform (e.g., creating a Linux repo from macOS), use the `--subdir` flag in the conda command (requires modifying the script to pass `['--subdir', 'linux-64']`).
-   **Updates:** To update the repo, re-run the script. It will download new versions if the solver picks them up. You must re-run `conda index` after adding files.
-   **Binaries:** This method grabs binaries. It does not build from source.

## Resources

-   [Conda Index Documentation](https://github.com/conda/conda-index)
-   [Conda Channels](https://docs.conda.io/projects/conda/en/latest/user-guide/concepts/channels.html)
