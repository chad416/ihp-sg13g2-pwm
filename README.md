# pwm3_top: 3-phase PWM with dead-time insertion, RTL to GDS on IHP SG13G2

A three-phase, centre-aligned motor-control PWM block (programmable dead time, latched
fault shutdown, SPI registers) taken from a written spec through formal proofs and a
model-based cocotb testbench to a DRC- and LVS-clean macro layout on the open IHP SG13G2
130 nm PDK, so that the shoot-through safety of the gate-drive outputs is proven rather
than only simulated.

Status: layout only. It has not been fabricated and nothing here was measured on
silicon. Every number below is read from tool output committed under `results/`.

## Signoff summary

Final run, LibreLane 3.1.0.dev3, `sg13g2_stdcell`, 100 MHz target
([results/impl/summary.md](results/impl/summary.md), generated from the flow's `metrics.json`).

| Check | Result |
|---|---|
| Setup worst slack, slow 1.08 V / 125 °C | **+1.158 ns** (typ 1.20 V / 25 °C: +4.328 ns, fast 1.32 V / -40 °C: +6.172 ns) |
| Hold worst slack, fast 1.32 V / -40 °C | **+0.107 ns** (slow: +0.604 ns, typ: +0.285 ns) |
| Setup and hold WNS / TNS, all three corners | 0 / 0 ns (no failing path) |
| Area | die 259.7 x 278.5 µm (0.072 mm²), 36,607 µm² standard cells, 60.0 % core utilisation |
| Cells | 2,462 standard cells, 288 flip-flops (plus fill and tap cells) |
| Power, typ corner | 2.12 mW, vectorless estimate (not from simulation activity) |
| DRC | KLayout with the IHP `ihp-sg13g2.drc` deck: 0; Magic: 0; antenna: 0 |
| LVS | Netgen: circuits match uniquely |
| Formal | unbounded proofs of no-overlap, dead time and fault latency; all covers reached |
| Simulation | 8/8 tests, 509,447 cycles compared with a reference model, 0 mismatches |
| Coverage | functional 39/39 bins; code: line, branch and toggle 100 % (Verilator) |

<img src="results/layout_pwm3_top.png" alt="Final layout of pwm3_top" width="480">

*KLayout render of [results/impl/final/pwm3_top.gds](results/impl/final/pwm3_top.gds) with
the IHP layer colours.*

**Reproduce everything** (lint, simulation, coverage, formal, RTL to GDS, signoff
reports and figures) with Docker and the pinned image `hpretl/iic-osic-tools:2026.10`:

```bash
scripts/run_all.sh                                          # Linux / macOS
powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1  # Windows, Docker Desktop
```

Details and run time are in [Reproduce](#reproduce).

## Architecture

```
 SPI (mode 0) --> 2-FF sync --> SPI slave --> register file --> time base --> 3x dead-time --> pwm_h_o[2:0]
                                (oversampled)  (pending regs)   (shadow regs)    (registered)  --> pwm_l_o[2:0]
 fault_i -------> 2-FF sync --> fault latch -------------- safe ----------------------^         --> sync_o
 rst_ni --------> 2-FF sync --> synchronous reset
```

- **Time base:** 16-bit up/down counter, `f_PWM = f_clk / (2 * PERIOD)`, duty =
  `CMPx / PERIOD`, pulses centred on the counter valley.
- **Shadow registers:** PERIOD, CMPA/B/C and DEADTIME load only at the valley, so a write
  cannot add an edge mid-period. A HOLD bit makes multi-register updates atomic.
- **Dead-time unit (per phase):** turn-off is immediate; turn-on needs both switches off
  for `max(DT, 1)` cycles. Shorter reference pulses are swallowed.
- **Fault:** `fault_i` sampled high at clock edge k forces all six outputs low at edge k+2
  (under 30 ns from the pin at 100 MHz). The fault is latched and only software can clear
  it, and only after the input has gone away.
- **Interfaces:** one clock, every asynchronous input through a 2-flop synchroniser, every
  output straight from a flip-flop. The SPI is oversampled, so there is no second clock
  domain and no CDC beyond the synchronisers.

Register map, timing contract and reset values: [SPEC.md](SPEC.md). Micro-architecture,
trade-offs and the timing-closure story: [DESIGN.md](DESIGN.md).

## Verification

| Layer | What it checks | Result |
|---|---|---|
| Lint | `verilator --lint-only -Wall`, no waivers | 0 warnings |
| Formal proof, dead-time unit | no overlap, dead time >= `max(DT,1)`, safe -> off; all inputs free; k-induction | PASS |
| Formal proof, full design | the same in context, fault latency, latched fault and OUTEN=0 keep outputs off; free SPI, fault and reset pins; k-induction | PASS |
| Formal covers | hand-over both ways, SPI write, fault clear; with `DT_W = 2` a low and a high side turn on at the pins (steps 55 and 104) | all reached |
| Deep BMC, `DT_W = 2` | 110 cycles, long enough for the outputs to switch | PASS |
| Formal mutation | 7 injected bugs (overlap, short dead time, ignored fault, slower fault path, ...) | 7/7 caught |
| cocotb regression | cycle-accurate Python model written from the spec, all 7 outputs compared every cycle; directed tests (duty 0 % and 100 %, `P = 0, 1, 0xFFFF`, `DT = 0`, pulse shorter than DT, period and compare change while running, HOLD, faults, aborted SPI frames) plus 120 constrained-random configurations | 8/8 pass on Icarus and on Verilator |
| Simulation mutation | 6 functional bugs outside the formal scope (compare off by one, HOLD ignored, ...) | 6/6 caught |

What "100 % coverage" means here, precisely:

- **Functional:** 39 bins in a small custom collector (period, duty and dead-time ranges,
  hand-overs, swallowed pulses, fault while high/low/in dead time, blocked and successful
  fault clear, HOLD updates, aborted SPI frames, reads of every register). Bins are
  sampled by the scoreboard from what the design did, not from what a test intended,
  and the regression fails on any empty bin.
- **Code:** the same regression on Verilator 5.052: line (block) 37/37, branch 44/44,
  toggle 1454/1454 bits. Expression and FSM coverage are not measured. Code under
  `ifdef FORMAL` is not part of it.

The random tests use a fixed seed (`PWM3_SEED`, default 20261028); other seeds:
`make -C tb PWM3_SEED=<n>`. Evidence: [results/formal/](results/formal/),
[results/sim/](results/sim/), [results/lint/](results/lint/).

| | |
|---|---|
| ![3-phase PWM](docs/screenshots/sim_pwm_3phase.png) | ![dead time](docs/screenshots/sim_deadtime_zoom.png) |
| Three phases from the cocotb run (pins recorded by the scoreboard) | Dead time on the pins: 7 cycles = 70 ns for DEADTIME = 7 |

## Physical design results

| Corner | Setup WS | Setup TNS | Hold WS | Hold TNS | f_max estimate |
|---|---|---|---|---|---|
| `nom_slow_1p08V_125C` | +1.158 ns | 0 | +0.604 ns | 0 | 113 MHz |
| `nom_typ_1p20V_25C` | +4.328 ns | 0 | +0.285 ns | 0 | 176 MHz |
| `nom_fast_1p32V_m40C` | +6.172 ns | 0 | +0.107 ns | 0 | 261 MHz |

f_max = 1 / (10 ns - setup WS), estimated from the 100 MHz run. `nom` is the only RC
extraction corner the PDK provides. Constraints: [flow/pwm3_top.sdc](flow/pwm3_top.sdc)
(0.25 ns clock uncertainty for setup and hold, +/-5 % derate, 20 % I/O delay).

- **Timing closure.** The first run met timing with only +0.143 ns at the slow corner. Its
  critical path went from the counter through a 16-bit zero detect into the shadow-load
  enable, which drives about 80 mux selects. Replacing the comparator with a registered
  zero flag (equivalence proven by k-induction) gave +1.158 ns for one extra flop and
  +1 % area. Details and both critical paths: DESIGN.md section 5.1.
- **Hold buffers.** 413 hold buffers were inserted, because the 0.25 ns uncertainty also
  applies to hold. One sits on today's worst setup path and costs 0.66 ns there.
- **Max-fanout warnings.** 24, all on clock-tree leaf buffers (fanout 10 to 15 against a
  limit of 8); slew and capacitance on these nets are within limits.
- **Flops.** The library has no flop without a reset pin, so all 288 flops are
  `sg13g2_dfrbpq_1` with `RESET_B` tied high (DESIGN.md section 3.9).
- **Power.** 2.12 mW at the typical corner: 70 % sequential, 27 % clock tree, with
  OpenSTA's default activity. A PWM's real activity is lower, so treat it as an upper
  estimate.

Signoff reports per corner: [results/impl/sta/](results/impl/sta/). DRC:
[results/impl/drc_klayout/](results/impl/drc_klayout/), LVS:
[results/impl/lvs_netgen/](results/impl/lvs_netgen/).

| | |
|---|---|
| ![fault](docs/screenshots/sim_fault_response.png) | ![layout detail](docs/screenshots/layout_detail_40x40um.png) |
| Fault shutdown on the pins | 40 x 40 µm layout detail |

Rendered report images (`term_*.png`) and LibreLane's own layout render are in
[docs/screenshots/](docs/screenshots/); they are generated from the committed result
files by `make results`.

## Limitations

- **Not fabricated.** Open PDK, open tools. The checks are what this flow offers for
  SG13G2, not a foundry signoff, and there is no silicon data.
- **Macro only.** No pad ring, ESD or board-level I/O timing; the I/O delays are a 20 %
  budget, not derived from a real interface.
- **DRC scope.** Full IHP KLayout deck (FEOL, BEOL, pin and forbidden-layer rules) with
  recommended rules off (LibreLane default). Metal-density rules are left for chip-level
  integration with fill.
- **Parasitics.** Nominal RC only; no RC-best/RC-worst corners.
- **Power** is vectorless, not from simulation activity (VCD/SAIF).
- **Synchronous reset (as specified).** The outputs are undefined until two clock edges
  after power-up; a board relies on the gate driver's enable or pull-downs.
- **SPI** is formally checked only for "cannot break safety"; its function is checked in
  simulation (read-back of every register, aborted frames).
- **Functional coverage** uses a small custom collector, not a UVM or cocotb-coverage
  database.

## Next steps

- Asynchronous-assert, synchronous-deassert reset, which would use the flops' existing
  `RESET_B` pins and make the outputs safe before the clock runs.
- Hold uncertainty separate from setup, and no hold fixing on the high-fanout `at_zero_q`
  net, to recover the 0.66 ns and most of the 22 % buffer area.
- Gate-level simulation of the final netlist with SDF back-annotation.
- Trip-zone style per-phase fault actions and a minimum off-time for bootstrap refresh
  (DESIGN.md section 6).

## Reproduce

Requirements: Docker (Docker Desktop with the WSL 2 backend on Windows) and about 17 GB of
disk for the image (4 GB download). Tool versions, including the IHP-Open-PDK commit
`a49358cc`, are pinned by the image and recorded in
[results/tool_versions.txt](results/tool_versions.txt).

```bash
scripts/run_all.sh                     # make all: lint sim coverage formal flow results
scripts/run_all.sh sim                 # or one target: lint | sim | coverage | formal | flow | results
```

On Windows use `powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1 [target]`.
On a 16-thread laptop under Docker Desktop, with the image already pulled, a fresh
clone runs `make all` to exit code 0 in 11 to 14 minutes, of which the LibreLane flow
takes 6 to 8. The regenerated implementation summary, formal summary, coverage
reports and mutation tables match the committed ones.

## Repository layout

```
SPEC.md     the contract: ports, registers, timing, verification requirements
DESIGN.md   micro-architecture, decisions, verification plan, timing closure
rtl/        synthesisable Verilog-2005 (formal properties under `ifdef FORMAL`)
tb/         cocotb testbench and Python reference model
formal/     SymbiYosys task files
flow/       LibreLane configuration, SDC, pin order
scripts/    one-command runner, mutation checks, result collection, figures
results/    committed evidence: logs, reports, coverage, final GDS and netlist
```

The final GDS (1.9 MB) and gate-level netlist (0.3 MB) are committed on purpose: they
are the deliverable the DRC, LVS and STA reports refer to. Full flow run directories are
not committed (`flow/runs/` is ignored).

## License

MIT for the RTL, testbench, scripts and documentation ([LICENSE](LICENSE)). The GDS and
layout images contain IHP-Open-PDK standard cells (Apache-2.0); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
