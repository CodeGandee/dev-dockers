# common-cu128

CUDA 12.8 (Ubuntu 24.04) base image with common pre-installed developer tools via PeiDocker.

## Quick start

```bash
cd dockers/common-cu128
cp env.example .env  # optional

# Apply post-create deltas -> run PeiDocker configure -> apply post-configure deltas
./pei-configure.sh --with-merged

# Build and run
docker compose -f src/docker-compose.yml build stage-2
docker compose -f src/docker-compose.yml up -d stage-2
```
