# Test Suite

## Structure
- **unit/**: Fast, deterministic unit tests. Discovered by CI.
- **integration/**: I/O, service, or multi-component tests.
- **manual/**: Manually executed scripts, not collected by CI.

## Guidelines
Prefer `pixi run` for executing tests. Keep unit tests hermetic.
