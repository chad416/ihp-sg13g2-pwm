"""Build a Markdown summary table from a LibreLane metrics.json.

Every number printed here is read from the tool output; nothing is typed in.
Usage: python3 summarize_impl.py <results/impl dir>
"""

import json
import sys
from pathlib import Path

impl = Path(sys.argv[1])
m = json.loads((impl / "metrics.json").read_text())
cfg = json.loads((impl / "resolved_config.json").read_text())
period = float(cfg["CLOCK_PERIOD"])


def get(key, default=None):
    return m.get(key, default)


def fmt(v, unit="", nd=3):
    if v is None:
        return "n/a"
    if isinstance(v, float):
        return f"{v:.{nd}f}{unit}"
    return f"{v}{unit}"


rows = [
    ("Clock constraint", f"{period:g} ns ({1000 / period:g} MHz)"),
    ("Die area", fmt(get("design__die__area"), " um^2", 1)),
    ("Core area", fmt(get("design__core__area"), " um^2", 1)),
    ("Std-cell area", fmt(get("design__instance__area__stdcell",
                              get("design__instance__area")), " um^2", 1)),
    ("Core utilisation", fmt(get("design__instance__utilization"), "", 3)),
    ("Instances (total)", fmt(get("design__instance__count"))),
    ("Std cells", fmt(get("design__instance__count__stdcell"))),
    ("Setup worst slack (all corners)", fmt(get("timing__setup__ws"), " ns")),
    ("Hold worst slack (all corners)", fmt(get("timing__hold__ws"), " ns")),
    ("Setup WNS / TNS", f"{fmt(get('timing__setup__wns'), ' ns')} / "
                        f"{fmt(get('timing__setup__tns'), ' ns')}"),
    ("Hold WNS / TNS", f"{fmt(get('timing__hold__wns'), ' ns')} / "
                       f"{fmt(get('timing__hold__tns'), ' ns')}"),
    ("Setup violations", fmt(get("timing__setup_vio__count"))),
    ("Hold violations", fmt(get("timing__hold_vio__count"))),
    ("Flip-flops", fmt(get("design__instance__count__class:sequential_cell"))),
    ("Hold buffers inserted", fmt(get("design__instance__count__hold_buffer"))),
    ("Max slew / cap / fanout violations",
     f"{fmt(get('design__max_slew_violation__count'))} / "
     f"{fmt(get('design__max_cap_violation__count'))} / "
     f"{fmt(get('design__max_fanout_violation__count'))}"),
    ("Clock skew (worst, setup)", fmt(get("clock__skew__worst_setup"), " ns")),
    ("Total power (typ corner)", fmt(get("power__total"), " W", 6)),
    ("  internal / switching / leakage",
     f"{fmt(get('power__internal__total'), ' W', 6)} / "
     f"{fmt(get('power__switching__total'), ' W', 6)} / "
     f"{fmt(get('power__leakage__total'), ' W', 9)}"),
    ("Wire length", fmt(get("route__wirelength"), " um")),
    ("Detailed-route DRC errors", fmt(get("route__drc_errors"))),
    ("KLayout DRC errors", fmt(get("klayout__drc_error__count"))),
    ("Magic DRC errors", fmt(get("magic__drc_error__count"))),
    ("LVS errors (Netgen)", fmt(get("design__lvs_error__count"))),
    ("Antenna violating nets", fmt(get("antenna__violating__nets"))),
]

print("| Metric | Value |\n|---|---|")
for k, v in rows:
    print(f"| {k} | {v} |")

# Per-corner setup/hold slack and the f_max it implies
corners = sorted({k.split("corner:")[1] for k in m if "timing__setup__ws__corner:" in k})
if corners:
    print("\n| Corner | Setup WS (ns) | Setup TNS (ns) | Hold WS (ns) | Hold TNS (ns) "
          "| Critical path (ns) | f_max estimate (MHz) |")
    print("|---|---|---|---|---|---|---|")
    for c in corners:
        s = m.get(f"timing__setup__ws__corner:{c}")
        h = m.get(f"timing__hold__ws__corner:{c}")
        if s is None:
            continue
        st = m.get(f"timing__setup__tns__corner:{c}")
        ht = m.get(f"timing__hold__tns__corner:{c}")
        crit = period - s
        print(f"| {c} | {s:.3f} | {fmt(st)} | {fmt(h)} | {fmt(ht)} | {crit:.3f} "
              f"| {1000 / crit:.0f} |")
    print("\nWS = worst slack, TNS = total negative slack (0 when no path fails). "
          "f_max estimate = 1 / (T_clk - setup WS) per corner, from the run constrained "
          "at the clock above; it is an estimate, not a separate run.")
