| Metric | Value |
|---|---|
| Clock constraint | 10 ns (100 MHz) |
| Die area | 72321.8 um^2 |
| Core area | 60972.9 um^2 |
| Std-cell area | 36607.3 um^2 |
| Core utilisation | 0.600 |
| Instances (total) | 5552 |
| Std cells | 2462 |
| Setup worst slack (all corners) | 1.158 ns |
| Hold worst slack (all corners) | 0.107 ns |
| Setup WNS / TNS | 0 ns / 0 ns |
| Hold WNS / TNS | 0 ns / 0 ns |
| Setup violations | 0 |
| Hold violations | 0 |
| Flip-flops | 288 |
| Hold buffers inserted | 413 |
| Max slew / cap / fanout violations | 0 / 0 / 24 |
| Clock skew (worst, setup) | 0.281 ns |
| Total power (typ corner) | 0.002124 W |
|   internal / switching / leakage | 0.001796 W / 0.000326 W / 0.000001784 W |
| Wire length | 65152 um |
| Detailed-route DRC errors | 0 |
| KLayout DRC errors | 0 |
| Magic DRC errors | 0 |
| LVS errors (Netgen) | 0 |
| Antenna violating nets | 0 |

| Corner | Setup WS (ns) | Setup TNS (ns) | Hold WS (ns) | Hold TNS (ns) | Critical path (ns) | f_max estimate (MHz) |
|---|---|---|---|---|---|---|
| nom_fast_1p32V_m40C | 6.172 | 0 | 0.107 | 0 | 3.828 | 261 |
| nom_slow_1p08V_125C | 1.158 | 0 | 0.604 | 0 | 8.842 | 113 |
| nom_typ_1p20V_25C | 4.328 | 0 | 0.285 | 0 | 5.672 | 176 |

WS = worst slack, TNS = total negative slack (0 when no path fails). f_max estimate = 1 / (T_clk - setup WS) per corner, from the run constrained at the clock above; it is an estimate, not a separate run.
