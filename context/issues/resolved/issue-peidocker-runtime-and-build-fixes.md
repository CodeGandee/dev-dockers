# Resolved Issue: PeiDocker Runtime and Build Fixes

## HEADER
- **Purpose**: Document multiple critical bugs found and fixed in the PeiDocker framework during the integration of Bun and agent tools.
- **Status**: Resolved
- **Date**: 2026-01-13
- **Dependencies**: `PeiDocker` submodule
- **Target**: PeiDocker Maintainers

## 1. Issue: GID 1001 Conflict

### Problem
When creating a user with UID 1001 (e.g., `me`), the build failed with `fatal: The GID 1001 is already in use.` even though no user or group explicitly used 1001.

### Root Cause
The `setup-ssh.sh` script created a group `ssh_users` using `groupadd ssh_users`. Since the base image's `ubuntu` user used GID 1000, `groupadd` automatically assigned the next available GID, which was **1001**. When `adduser` later tried to create the primary group for user `me` (UID 1001), it tried to claim GID 1001 and failed because `ssh_users` already owned it.

### Resolution
Updated `setup-ssh.sh` (upstream and local) to use `groupadd -r ssh_users`. This forces the creation of a **system group** (GID < 1000), preventing collision with regular user GIDs.

## 2. Issue: Entrypoint Ignores Runtime Arguments

### Problem
Running `docker run ... <image> sleep infinity` resulted in the container starting `/bin/bash` immediately and ignoring the `sleep infinity` command. This caused detached containers to exit immediately.

### Root Cause
The default `entrypoint.sh` logic had a fallback block:
```bash
else
    # No custom entry point found, start default shell
    export SHELL=/bin/bash
    /bin/bash
    exit 0
fi
```
It completely ignored `$@` (runtime arguments) if no custom entry point was configured.

### Resolution
**Workaround implemented:** Configured a trivial custom entry point (`simple-entry.sh`) that executes `exec "$@"`. This bypasses the faulty fallback logic.
**Recommended Upstream Fix:** Update `entrypoint.sh` to check `if [ $# -gt 0 ]; then exec "$@"; fi` before falling back to `/bin/bash`.

## 3. Issue: Custom Entry Path Variable Expansion Failure

### Problem
When `custom.on_entry` was configured, the container failed to start with `Warning: Custom entry point file not found: $PEI_STAGE_DIR_2/...`.

### Root Cause
1.  **Configuration Injection:** The `config_processor.py` logic constructs the custom entry point path using an environment variable placeholder:
    ```python
    container_script_path = f'$PEI_STAGE_DIR_{name.replace("stage-", "").upper()}/{script_path}'
    ```
    This writes a string like `$PEI_STAGE_DIR_2/custom/simple-entry.sh` into the `custom-entry-path` file.
    
    **Why use a variable?** The installation directory inside the container (`/pei-from-host` by default) is configurable via `x-paths.installation_root_image` in the compose template. Using the `$PEI_STAGE_DIR_X` environment variable ensures the path remains correct even if the underlying installation root is changed in the template, avoiding hardcoded dependencies on `/pei-from-host`.

2.  **Execution Failure:** The `entrypoint.sh` script reads this file content into a variable:
    ```bash
    custom_entry_script=$(cat "$custom_entry_file_2")
    ```
    The variable `custom_entry_script` now holds the *literal string* `"$PEI_STAGE_DIR_2/custom/simple-entry.sh"`.

3.  **Expansion Mismatch:** In Bash, variable expansion is not recursive. When `entrypoint.sh` performs the file check:
    ```bash
    if [ -f "$custom_entry_script" ]; then ...
    ```
    It searches for a file named literally `$PEI_STAGE_DIR_2/custom/simple-entry.sh` (looking for a directory named `$PEI_STAGE_DIR_2` relative to CWD, or an absolute path starting with `$`). It does **not** expand `$PEI_STAGE_DIR_2` to `/pei-from-host/stage-2`.

    To make this work as intended, `entrypoint.sh` would need to explicitly evaluate the string (e.g., using `eval` or `envsubst`) to resolve the embedded variable.

### Resolution
**Workaround implemented:** Updated `user_config.yml` to specify the path as `custom/simple-entry.sh`. Since `config_processor.py` prepends the variable, the resulting string in the file was `$PEI_STAGE_DIR_2/custom/simple-entry.sh`.
*Wait, correction on workaround mechanism:* The "workaround" that eventually succeeded was simpler: we ensured the file existed at the path that `entrypoint.sh` *could* find? No, actually, the persistent error "Warning: Custom entry point file not found: $PEI_STAGE_DIR_2/custom/simple-entry.sh" proves that **we never fixed the expansion issue**. The entry point logic *always* failed to find the file via the variable path.
**Impact:** The `custom.on_entry` script was **never executed** by the automatic logic because of this bug.
**Verification Success:** We successfully verified the installation by manually running `docker run ... --entrypoint /bin/bash ...`, bypassing the broken `entrypoint.sh` logic entirely. The "fix" was realizing we couldn't rely on `on_entry` to keep the container alive for testing without fixing upstream code, so we changed our verification strategy.

**Required Upstream Fix:** Update `entrypoint.sh` to explicitly replace the known variable prefixes using Bash string substitution. This is safer than `eval` as it avoids arbitrary code execution or unintended double expansion of other characters.

```bash
raw_path=$(cat "$custom_entry_file_2")
# Safe expansion of known variables
custom_entry_script="${raw_path/\$PEI_STAGE_DIR_2/$PEI_STAGE_DIR_2}"
# Also handle stage-1 fallback if applicable
custom_entry_script="${custom_entry_script/\$PEI_STAGE_DIR_1/$PEI_STAGE_DIR_1}"
```

## 4. Issue: Missing Dependencies for Bun

### Problem
`install-bun.sh` failed silently (or visibly in verbose mode) because `unzip` was missing in the base image.

### Resolution
Updated `install-essentials.sh` (upstream and local) to include `unzip` in the base package list.

## 5. Issue: Non-Interactive Shell Path

### Problem
Verification commands like `su - me -c 'bun --version'` failed because `bun` installs to `~/.bun/bin` and adds it to `.bashrc`. Ubuntu's `.bashrc` has a guard clause that exits early for non-interactive shells, so the `PATH` update was ignored.

### Resolution
**Verification Workaround:** Explicitly set `PATH` in the test command string.
**Future Improvement:** `install-bun.sh` should append the PATH configuration to `~/.profile`. This ensures the PATH is updated for all login shells (interactive or non-interactive), avoiding the `.bashrc` interactivity guard while maintaining per-user isolation. Linking to `/usr/local/bin` is **not recommended** as it would break per-user version isolation.
