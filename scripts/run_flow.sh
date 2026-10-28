#!/usr/bin/env bash
# RTL-to-GDS with LibreLane (Classic flow) on IHP SG13G2, sg13g2_stdcell.
# The flow runs in a container-local scratch directory (bind mounts on Docker
# Desktop are slow for the many small files a run writes). Afterwards only the
# signoff evidence (final views, STA, DRC, LVS, synthesis and antenna reports,
# logs) is copied back to flow/runs/<tag>/ (git-ignored); curated reports go to
# results/ via scripts/collect_results.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${RUN_TAG:-final}
CONFIG=${FLOW_CONFIG:-config.json}
WORK=${FLOW_WORK:-/tmp/pwm3_flow}

rm -rf "$WORK"
mkdir -p "$WORK"
cp -r "$ROOT/rtl" "$ROOT/flow" "$WORK/"
rm -rf "$WORK/flow/runs"

cd "$WORK/flow"
start=$(date +%s)
librelane --manual-pdk --pdk-root "$PDK_ROOT" --pdk ihp-sg13g2 --scl sg13g2_stdcell \
  --run-tag "$TAG" --overwrite "$CONFIG" 2>&1 | tee "$WORK/flow.log"
echo "flow wall time: $(( $(date +%s) - start )) s" | tee -a "$WORK/flow.log"

RUN="$WORK/flow/runs/$TAG"
cp "$WORK/flow.log" "$RUN/flow_console.log"
cd "$RUN"
keep=(final resolved.json error.log warning.log flow.log flow_console.log)
for pat in yosys-synthesis openroad-stapostpnr klayout-drc magic-drc netgen-lvs \
           openroad-checkantennas-1 klayout-render openroad-irdropreport; do
  keep+=($(ls -d *-"$pat" 2>/dev/null || true))
done
rm -rf "$ROOT/flow/runs/$TAG"
mkdir -p "$ROOT/flow/runs/$TAG"
tar -cf - "${keep[@]}" | tar -C "$ROOT/flow/runs/$TAG" -xf -
echo "signoff evidence copied to flow/runs/$TAG"
