#!/usr/bin/env bash
# RTL code coverage: run the same cocotb regression on Verilator with line,
# branch and toggle coverage, summarise it with verilator_coverage and fail if
# any metric is below 100 %. This also checks that the testbench gives the
# same result on a second simulator (the main regression runs on Icarus).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/results/sim/code_coverage.txt"
TB="$ROOT/tb"
BUILD="$TB/sim_build_verilator"
mkdir -p "$(dirname "$OUT")"
rm -rf "$BUILD" "$TB/coverage.dat"

make -C "$TB" SIM=verilator SIM_BUILD="$BUILD" \
  EXTRA_ARGS="--coverage-line --coverage-toggle" \
  COCOTB_RESULTS_FILE="$BUILD/results.xml" \
  PWM3_COV_REPORT="$BUILD/functional_coverage.txt" PWM3_TRACE_DIR="$BUILD/traces" \
  >"$BUILD.log" 2>&1 || { tail -n 40 "$BUILD.log"; exit 1; }
mv "$TB/coverage.dat" "$BUILD/coverage.dat"

{
  echo "Simulator: $(verilator --version)"
  python3 "$ROOT/scripts/check_junit.py" "$BUILD/results.xml" "$BUILD.log" | tail -n 3
  echo
  verilator_coverage --report summary,hier "$BUILD/coverage.dat"
} | tee "$OUT"

# Gate: every line, branch and toggle point must be hit at least once.
rc=0
for kind in line branch toggle; do
  pct=$(awk -v k="$kind" '$1 == k && $2 == ":" {print $3; exit}' "$OUT" | tr -d '%')
  if [[ "$pct" != "100.0" ]]; then
    echo "code coverage: $kind = ${pct:-missing} % (not 100 %)"; rc=1
  fi
done
if [[ $rc -ne 0 ]]; then
  verilator_coverage --annotate "$BUILD/annotated" --annotate-points --annotate-min 1 \
    "$BUILD/coverage.dat" >/dev/null
  echo "uncovered points:"; grep -h '^-000000' "$BUILD"/annotated/*.v | sort -u | head -n 40
fi
exit $rc
