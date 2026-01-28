# model-bench-cu128

Build a CUDA 12.8 (Ubuntu 24.04) model benchmarking image via PeiDocker.

## Quick start

```bash
cd dockers/model-bench-cu128

# Configure (generates/refreshes src/docker-compose.yml, src/merged.Dockerfile, etc.)
./pei-configure.sh --with-merged

# Build final image tag
./src/build-merged.sh -o ig-model-bench:cu128 -- --progress=plain
```

## Run

```bash
docker compose -f src/docker-compose.yml up -d stage-2
```

## Notes

- Requirements: `memo/req-docker.md`
- Plan + TODOs: `memo/plan-ig-model-bench-cu128.md`
- `.env` is not tracked; copy from `env.example` if you need to override ports.
