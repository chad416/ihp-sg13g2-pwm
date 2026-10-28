#!/usr/bin/env bash
# Mutation check for the simulation testbench: functional bugs that the formal
# safety properties deliberately do not cover (counter, compare, shadow timing,
# register decode) must each make the cocotb regression fail.
# Runs on a temporary copy; the repository's RTL is never modified.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/results/sim/mutation.txt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$OUT")"

# id # file # sed script # description
MUTANTS=(
  "S1#pwm_timebase.v#s/cmp_ref = down ? (cnt <= c) : (cnt < c);/cmp_ref = down ? (cnt <= c) : (cnt <= c);/#compare off by one while counting up"
  "S2#pwm_timebase.v#s/load = ~hold_i & (~en_i | at_zero);/load = (~en_i | at_zero);/#shadow transfer ignores HOLD"
  "S3#pwm_timebase.v#s/if (cnt_o >= per_m1) begin/if (cnt_o >= per_e) begin/#counter turns one count late (period 2P+2)"
  "S4#pwm_timebase.v#s/wire             at_zero = (cnt_o == {CNT_W{1'b0}});/wire             at_zero = (cnt_o == {CNT_W{1'b0}}) | dir_o;/#shadow registers also load at the peak"
  "S5#pwm_spi_slave.v#s/waddr_o <= rx_q\[18:15\];/waddr_o <= rx_q[19:16];/#SPI write address decoded from wrong bits"
  "S6#pwm_regs.v#s/dt_o    <= {DT_W{1'b1}};  \/\/ fail-safe/dt_o    <= {DT_W{1'b0}};  \/\/ fail-safe/#dead time resets to 0 instead of maximum"
)

printf '%-4s %-46s %s\n' ID "Mutation" "Result" | tee "$OUT"
rc=0
for m in "${MUTANTS[@]}"; do
  IFS='#' read -r id file expr desc <<<"$m"
  d="$WORK/$id"
  mkdir -p "$d"
  cp -r "$ROOT/rtl" "$d/"
  mkdir -p "$d/tb" && cp "$ROOT"/tb/*.py "$ROOT/tb/Makefile" "$d/tb/"
  sed -i "$expr" "$d/rtl/$file"
  if cmp -s "$ROOT/rtl/$file" "$d/rtl/$file"; then
    res="ERROR (mutation did not apply)"; rc=1
  else
    (cd "$d/tb" && make SIM=icarus PWM3_RANDOM_CFGS=20 PWM3_COV_REPORT="$d/cov.txt" >"$d/sim.log" 2>&1)
    nfail=$(grep -o 'FAIL=[0-9]*' "$d/sim.log" | tail -1 | cut -d= -f2)
    if [[ -n "$nfail" && "$nfail" -gt 0 ]]; then
      first=$(grep -oE 'test_pwm3\.test_[a-z_]+ +FAIL' "$d/sim.log" | head -1 | awk '{print $1}')
      res="killed ($nfail failing tests, first: ${first#test_pwm3.})"
    else
      res="SURVIVED"; rc=1
    fi
  fi
  printf '%-4s %-46s %s\n' "$id" "$desc" "$res" | tee -a "$OUT"
  rm -rf "$d"
done
exit $rc
