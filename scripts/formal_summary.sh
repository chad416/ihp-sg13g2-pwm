#!/usr/bin/env bash
# Print the status of every SymbiYosys task and fail if any task did not pass.
# Also copies each task's log next to the summary (results/formal/).
set -euo pipefail
cd "$(dirname "$0")/../formal"
mkdir -p ../results/formal
rc=0
for d in pwm_deadtime_prove pwm_deadtime_cover pwm3_top_prove pwm3_top_cover pwm3_top_cover_dt2 pwm3_top_bmc_dt2; do
  if [[ -f "$d/status" ]]; then
    st=$(cut -d' ' -f1 "$d/status")
    cp "$d/logfile.txt" "../results/formal/$d.log"
  else
    st=MISSING
  fi
  printf '%-22s %s\n' "$d" "$st"
  [[ "$st" == PASS ]] || rc=1
done
exit $rc
