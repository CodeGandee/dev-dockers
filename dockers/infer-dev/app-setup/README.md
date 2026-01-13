# Application Setup Log

This directory contains chronological logs of the manual setup steps performed to configure inference environments (e.g., `llama.cpp`, `vllm`) inside the `infer-dev:stage-2` container.

## Purpose
The goal is to experiment and validate the installation and configuration process interactively. Once a setup is verified, the steps documented here will be condensed into automated shell scripts (e.g., `install-llama-cpp.sh`) and integrated into the PeiDocker `user_config.yml` for reproducible builds.

## Naming Convention
Files should be named using the format: `<timestamp>-<topic>.md`.
Example: `20240113-1430-setup-llama-cpp-python.md`

## Workflow
1.  **Experiment**: Run commands interactively in the container.
2.  **Document**: Record the successful commands and any necessary context in a new markdown file in this directory.
3.  **Verify**: Confirm the setup works as expected.
4.  **Automate**: Create a `.sh` script based on the documentation and add it to the project's `installation/stage-2/custom` folder (or similar).
5.  **Integrate**: Add the script to `user_config.yml` `on_build` or `on_first_run` list.
