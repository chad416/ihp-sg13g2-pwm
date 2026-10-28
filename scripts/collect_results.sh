#!/usr/bin/env bash
# Copy the signoff evidence of a LibreLane run into results/impl/ (committed),
# render the layout PNG and write a machine-generated summary table.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${RUN_TAG:-final}
RUN="$ROOT/flow/runs/$TAG"
OUT="$ROOT/results/impl"
[[ -d "$RUN" ]] || { echo "no run at $RUN (run 'make flow' first)"; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT/sta" "$OUT/logs"

# last step directory whose name ends in the given suffix
step() { find "$RUN" -maxdepth 1 -type d -name "*-$1" | sort -t- -k1,1n | tail -n1; }

cp "$RUN/final/metrics.json" "$OUT/metrics.json"
cp "$RUN/resolved.json" "$OUT/resolved_config.json"
[[ -s "$RUN/warning.log" ]] && cp "$RUN/warning.log" "$OUT/logs/warning.log"
[[ -s "$RUN/error.log" ]] && cp "$RUN/error.log" "$OUT/logs/error.log"

# multi-corner post-PnR STA (one subdirectory per corner)
STA=$(step openroad-stapostpnr)
cp "$STA"/summary.rpt "$OUT/sta/" 2>/dev/null || true
for c in "$STA"/*/; do
  n=$(basename "$c")
  mkdir -p "$OUT/sta/$n"
  for f in power.rpt wns.max.rpt wns.min.rpt ws.max.rpt ws.min.rpt \
           tns.max.rpt tns.min.rpt skew.max.rpt skew.min.rpt checks.rpt; do
    [[ -f "$c/$f" ]] && cp "$c/$f" "$OUT/sta/$n/"
  done
  # full path reports are ~2 MB each; keep the worst paths (first 400 lines)
  for f in max.rpt min.rpt; do
    [[ -f "$c/$f" ]] && head -n 400 "$c/$f" > "$OUT/sta/$n/$f"
  done
done
cp "$STA"/*.log "$OUT/logs/" 2>/dev/null || true

# synthesis statistics, DRC, LVS, antenna
cp "$(step yosys-synthesis)"/reports/stat.rpt "$OUT/synth_stat.rpt" 2>/dev/null ||
  cp "$(step yosys-synthesis)"/reports/*.rpt "$OUT/" 2>/dev/null || true
DRC=$(step klayout-drc)
[[ -n "$DRC" ]] && cp -r "$DRC"/reports "$OUT/drc_klayout" 2>/dev/null || true
[[ -n "$DRC" ]] && cp "$DRC"/*.log "$OUT/logs/" 2>/dev/null || true
LVS=$(step netgen-lvs)
[[ -n "$LVS" ]] && cp -r "$LVS"/reports "$OUT/lvs_netgen" 2>/dev/null || true
ANT=$(step openroad-checkantennas-1)
[[ -n "$ANT" ]] && cp -r "$ANT"/reports "$OUT/antenna" 2>/dev/null || true

# final views: GDS (small macro, committed), gate-level netlist, SDC
mkdir -p "$OUT/final"
cp "$RUN"/final/gds/*.gds "$OUT/final/"
cp "$RUN"/final/nl/*.nl.v "$OUT/final/" 2>/dev/null || true
cp "$RUN"/final/sdc/*.sdc "$OUT/final/" 2>/dev/null || true

[[ -f "$OUT/lvs_netgen/lvs.netgen.rpt" ]] && tail -n 25 "$OUT/lvs_netgen/lvs.netgen.rpt" > "$OUT/lvs_netgen/lvs_tail.txt"

# layout images: full die, a 40 x 40 um detail, and LibreLane's own render
SHOTS="$ROOT/docs/screenshots"
mkdir -p "$SHOTS"
LYP="$PDK_ROOT/ihp-sg13g2/libs.tech/klayout/tech/sg13g2.lyp"
klayout -b -r "$ROOT/scripts/render_gds.py" -rd gds="$OUT/final/pwm3_top.gds" \
  -rd png="$ROOT/results/layout_pwm3_top.png" -rd lyp="$LYP" -rd width=2000
klayout -b -r "$ROOT/scripts/render_gds.py" -rd gds="$OUT/final/pwm3_top.gds" \
  -rd png="$SHOTS/layout_detail_40x40um.png" -rd lyp="$LYP" -rd width=1600 -rd box=110,120,150,160
cp "$RUN/final/render/pwm3_top.png" "$SHOTS/layout_librelane_render.png" 2>/dev/null || true

python3 "$ROOT/scripts/summarize_impl.py" "$OUT" | tee "$OUT/summary.md"
