#!/usr/bin/env bash
# One-command reproduction on Linux/macOS (Docker):
#   scripts/run_all.sh          # make all
#   scripts/run_all.sh formal   # one target
# Runs every step inside the pinned iic-osic-tools container.
set -euo pipefail
IMAGE=hpretl/iic-osic-tools:2026.10
REPO=$(cd "$(dirname "$0")/.." && pwd)
exec docker run --rm -v "$REPO:/foss/designs/pwm3" -w /foss/designs/pwm3 \
  --user "$(id -u):$(id -g)" "$IMAGE" --skip make "${1:-all}"
