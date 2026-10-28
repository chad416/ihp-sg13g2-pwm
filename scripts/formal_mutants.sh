#!/usr/bin/env bash
# Mutation check for the formal properties: inject realistic bugs into a
# temporary copy of the RTL and require that the formal check FAILS for every
# mutant. A property set that still passes on a broken design would be vacuous.
# The repository's RTL is never modified.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/results/formal/mutation.txt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$OUT")"

# id # file # sed script # sby file # task # description
MUTANTS=(
  "M1#pwm_deadtime.v#s/ & (off_cnt_q >= dt_eff);/;/#pwm_deadtime.sby#prove#no dead-time wait (only 1 off cycle)"
  "M2#pwm_deadtime.v#/end else if (ref_i) begin/{n;s/h_d = h_o | gap_ok;/h_d = 1'b1;/;n;s/l_d = 1'b0;/l_d = l_o;/}#pwm_deadtime.sby#prove#high side on at once, low side kept on (overlap)"
  "M3#pwm_deadtime.v#s/off_cnt_q >= dt_eff/off_cnt_q >= dt_eff - ONE/#pwm_deadtime.sby#prove#dead time one cycle short"
  "M4#pwm_deadtime.v#s/if (safe_i) begin/if (1'b0) begin/#pwm3_top.sby#bmc_dt2#safe request ignored by dead-time unit"
  "M5#pwm3_top.v#s/wire safe = fault_s | /wire safe = /#pwm3_top.sby#bmc_dt2#fault path one cycle slower (latch only)"
  "M6#pwm3_top.v#s/else if (fault_s) fault_latched_q <= 1'b1;/else if (fault_s) fault_latched_q <= 1'b0;/#pwm3_top.sby#bmc_dt2#fault never latched"
  "M7#pwm_regs.v#s/A_CTRL: begin/A_CMPA: begin/#pwm3_top.sby#bmc_dt2#CTRL decoded at wrong address (FCLR path)"
)

printf '%-4s %-50s %-22s %s\n' ID "Mutation" "Check" "Result" | tee "$OUT"
rc=0
for m in "${MUTANTS[@]}"; do
  IFS='#' read -r id file expr sby task desc <<<"$m"
  d="$WORK/$id"
  mkdir -p "$d/formal"
  cp -r "$ROOT/rtl" "$d/"
  cp "$ROOT"/formal/*.sby "$d/formal/"
  sed -i "$expr" "$d/rtl/$file"
  if cmp -s "$ROOT/rtl/$file" "$d/rtl/$file"; then
    res="ERROR (mutation did not apply)"; rc=1
  else
    (cd "$d/formal" && sby -f "$sby" "$task" >/dev/null 2>&1)
    st=$(cut -d' ' -f1 "$d/formal/${sby%.sby}_${task}/status" 2>/dev/null || echo MISSING)
    if [[ "$st" == FAIL ]]; then res="killed (check FAILS as expected)"; else res="SURVIVED ($st)"; rc=1; fi
  fi
  printf '%-4s %-50s %-22s %s\n' "$id" "$desc" "${sby%.sby}:$task" "$res" | tee -a "$OUT"
  rm -rf "$d"
done
exit $rc
