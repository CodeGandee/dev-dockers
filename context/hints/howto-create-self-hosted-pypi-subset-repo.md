# How to Create a Self-Hosted PyPI Subset Repository

This guide explains how to create a local PyPI mirror that contains only a specific subset of packages, while ensuring **all dependencies** are included so it is fully installable offline.

## Overview

1.  **Resolve**: Use `pip download` to fetch the package and its full dependency tree.
2.  **Organize**: Place the downloaded artifacts (wheels/sdists) into a directory.
3.  **Index**: Generate a "simple" repository index (PEP 503) using a tool like `pypi-mirror` or `dir2pi`.

## Prerequisites

-   `pip` installed.
-   `python3` installed.

## Step-by-Step Guide

### 1. Download Packages and Dependencies

The most reliable way to get a consistent set of dependencies is to use `pip download`. It uses the exact same resolution logic as `pip install`.

**Command:**
```bash
# Create a directory for the packages
mkdir -p local-pypi/packages

# Download package(s) and ALL dependencies
# --dest: Where to save the files
# --platform: (Optional) Specify target platform (e.g., manylinux2014_x86_64) if different from host
# --python-version: (Optional) Specify target python version (e.g., 3.10)
# --only-binary=:all: (Optional) Prefer wheels to avoid building from source
pip download 
    --dest local-pypi/packages 
    pandas scikit-learn 
    --platform manylinux2014_x86_64 
    --python-version 310 
    --only-binary=:all: 
    --implementation cp 
    --abi cp310
```

*Note: If you are mirroring for the **same** OS/Python version you are running on, you can omit the `--platform`, `--python-version`, `--implementation`, and `--abi` flags.*

### 2. Index the Repository

Raw files in a directory aren't enough for a standards-compliant PyPI mirror. You need a standard "simple" index (directory structure with `index.html` files).

We can use `pypi-mirror` or `dir2pi` (from `pip2pi`) or just a simple script. `pypi-mirror` is a good modern choice, but `dir2pi` is a classic.

**Option A: Using `dir2pi` (Simple)**

```bash
pip install pip2pi

# Generate the 'simple' index structure inside local-pypi
dir2pi local-pypi/packages
```

This creates a `local-pypi/packages/simple/` directory.

**Option B: Using `hashin` / Custom Script**

If you want a minimal, static HTML generator:

```bash
pip install passlib  # often needed for pypiserver tools
# There are many tools, but even a basic `python -m http.server` 
# combined with --find-links works without a full index structure.
```

### 3. Usage

**Option A: File System (No Server)**

You can install directly from the directory without a formal index if you use `--find-links` (or `-f`).

```bash
pip install --no-index --find-links=./local-pypi/packages pandas
```

**Option B: Static HTTP Server**

Serve the directory created by `dir2pi` (which has a `simple` folder).

```bash
cd local-pypi/packages
python3 -m http.server 8080
```

Install using the custom index URL:

```bash
pip install --index-url http://localhost:8080/simple/ pandas
```

## Advanced: Mirroring for Multiple Platforms

If you need to support multiple platforms (e.g., Linux servers and Mac laptops), you must run the `pip download` command multiple times with different platform constraints, pointing to the same destination directory.

```bash
# For Linux
pip download --dest local-pypi/packages --platform manylinux2014_x86_64 ... pandas

# For MacOS ARM
pip download --dest local-pypi/packages --platform macosx_11_0_arm64 ... pandas
```

## Resources

-   [pip download documentation](https://pip.pypa.io/en/stable/cli/pip_download/)
-   [pip2pi (dir2pi)](https://github.com/wolever/pip2pi)
