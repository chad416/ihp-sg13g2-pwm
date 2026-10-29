# DESIGN: pwm3_top micro-architecture and decisions

Companion to [SPEC.md](SPEC.md) (what the block does) and [README.md](README.md)
(results). This file explains *how* it is built and *why*.

## 1. Block diagram

```
                 +-----------+   wr/addr/data   +----------+  pending regs  +---------------+
 spi_sclk_i ---> |           | ---------------> |          | -------------> |  pwm_timebase |
 spi_cs_ni  ---> | 2-FF sync | -> pwm_spi_slave |  pwm_regs|                |  shadow regs  |
 spi_mosi_i ---> |  (x4)     |    (oversampled) |          | <-- status --- |  up/dn counter|
 spi_miso_o <--- |           | <--------------- |          |                |  3x compare   |
                 |           |                  +----------+                +-------+-------+
 fault_i    ---> |           | --fault_s--> [fault latch] --+                        | ref[2:0], dt_act
                 +-----------+                              | safe                   v
 rst_ni ---> [2-FF reset sync] --> rst (synchronous)        +------------> 3x pwm_deadtime ---> pwm_h_o[2:0]
                                                                            (registered)   ---> pwm_l_o[2:0]
                                                             pwm_timebase ----------------> sync_o
```

| Module | Function | Flops (counted from RTL) |
|--------|----------|-------|
| `pwm_sync2` ×2 | 2-flop synchronisers: reset (1 bit) + SCLK/CS/MOSI/fault (4 bits) | 10 |
| `pwm_spi_slave` | oversampled SPI mode-0 slave, 24-bit frames | 67 |
| `pwm_regs` | CTRL + pending PERIOD/CMPx/DEADTIME, read mux | 78 |
| `pwm_timebase` | shadow registers, up/down counter, zero flag, compares | 96 |
| `pwm_deadtime` ×3 | complementary pair + 10-bit dead-time counter | 36 |
| `pwm3_top` | fault latch | 1 |
| **Total** | | **288** |

Cross-check: the final netlist has 288 flip-flops (`results/impl/synth_stat.rpt`,
`metrics.json`), and iteration 1, which did not have the zero flag (section 5.1), had
287. So no flop was optimised away or duplicated.

## 2. Clock target: 100 MHz

- **Application need.** Industrial servo inverters switch at 8–20 kHz (Si IGBT) up to
  ~100 kHz (SiC/GaN MOSFET). At 100 MHz and 20 kHz centre-aligned PWM the period is
  `P = 2500`, i.e. 11.3 bit duty resolution; dead time is set in 10 ns steps, which is
  fine for the 0.3–3 µs dead times used with IGBTs and SiC modules. Commercial MCU
  timers (TI C2000 ePWM, NXP eFlexPWM, STM32 advanced timers) run in the same
  100–200 MHz range.
- **Technology.** The critical path is a 16-bit compare/increment plus a mux (about 15–20
  gate levels). In SG13G2 at the slow corner (1.08 V, 125 °C) that easily fits in 10 ns;
  the achieved slack and the derived f_max are reported, not assumed (section 5.1 and
  `results/impl/summary.md`).
- **Power.** Every flop toggles with the clock; there is no benefit in running faster
  than the PWM resolution the application needs.
- Going faster would not buy useful dead-time resolution anyway: for GaN (sub-10 ns
  dead time) the right answer is a delay-line high-resolution PWM, not a faster clock.

## 3. Key decisions and trade-offs

**3.1 Shoot-through prevention by construction, not by timing.**
`pwm_deadtime` lets a switch turn on only when *both* outputs have been off for
`DT_eff` cycles. Turning off is immediate. Compared with the common "delay the rising
edge of each signal" implementation, this has no corner case where two delayed edges can
overlap (e.g. a dead-time register change mid-transition, or a reference pulse shorter
than the dead time). The price is that very narrow pulses are swallowed, which is what a
power stage needs anyway (a pulse shorter than the dead time would never fully turn the
switch on).

**3.2 `DT = 0` clamped to 1 cycle.** A zero-cycle hand-over (high-side off and low-side
on at the same clock edge) relies on the gate driver's own propagation-delay matching.
The hardware refuses to do it; software cannot program a hazard.

**3.3 Fail-safe reset values.** `DEADTIME` resets to the maximum (10.23 µs) and
`OUTEN = 0`, so an unprogrammed or half-programmed device keeps all switches off.

**3.4 Registered outputs only.** All six gate signals come straight from flip-flops,
never from combinational logic, so they cannot glitch when the compare inputs change.
The synthesis flow is told nothing special; this is visible in the netlist (each output
pin is driven by a DFF Q pin through at most a buffer).

**3.5 Synchronous fault path, N = 3 cycles (30 ns).** `fault_i` goes through the same
2-flop synchroniser as everything else, then directly into the output flops' D logic.
An asynchronous "kill" path (fault gating the outputs combinationally) would be faster
(~1 ns) but brings in metastability and glitch risk on the very signals that must never
glitch, and cannot be verified with the same synchronous formal model. Real inverters
put the fastest protection (desaturation detection, ~1–5 µs, or cycle-by-cycle current
limit) in the analog gate driver; a 30 ns digital latency is two orders of magnitude
below that, so it costs nothing in practice.

**3.6 Latched fault, cleared only by software and only when the fault is gone.**
A fault that clears itself would let the inverter restart into the same short circuit.

**3.7 Shadow registers loaded at the valley + HOLD bit.** Loading at `CNT = 0` (the
centre of the pulse) is the standard "load on zero" scheme: no extra edges can ever be
generated within a period. HOLD gives software an atomic update of all three phases and
the period, which matters for space-vector modulation where the three duties belong
together.

**3.8 Oversampled SPI instead of an SPI clock domain.** Using SCLK as a clock would create
a second clock domain with CDC on every register. Oversampling keeps the design single-
clock and lets the formal proofs cover the register interface with free inputs. The cost
is `f_SCLK <= f_clk/10` (10 MHz), which is more than enough for a few register writes
per PWM period (one 24-bit write takes 2.4 µs; a 20 kHz period is 50 µs).

**3.9 Synchronous reset (as specified), and its known gap.** The project spec asks for a
synchronous reset. The consequence: until the clock runs and two edges have passed, the
output flops are undefined. On a real board the gate driver's enable / UVLO keeps the
power stage off during power-up, or the outputs have pull-downs and a tri-state pad. An
alternative with asynchronous assertion on the six output flops only would close that
gap; it is listed under limitations rather than silently changed.

The library makes the alternative cheap. `sg13g2_stdcell` has no flop without a reset
pin, so synthesis maps all 288 flops to `sg13g2_dfrbpq_1` and ties every `RESET_B`
high with its own `sg13g2_tiehi` cell (288 of them in
[results/impl/synth_stat.rpt](results/impl/synth_stat.rpt)), while the synchronous reset
costs an AND/mux term in front of each D input. Asynchronous assertion with synchronous
de-assertion (through the existing reset synchroniser) would use the pin that is already
there. I would make that change in a next revision.

## 4. Verification strategy

| Layer | What it proves | Tool |
|-------|----------------|------|
| Formal, module | Dead-time unit with **unconstrained** inputs: no overlap, every turn-on preceded by ≥ `DT_eff` both-off cycles, safe → off next edge. Unbounded (k-induction). The checker observes only the output pins. | SymbiYosys + Yices |
| Formal, top | Whole design with free SPI pins, fault and reset: all of the above in context, fault latency ≤ 3 cycles, latched fault / OUTEN=0 keep outputs off. Unbounded. | SymbiYosys + Yices |
| Formal, cover | The proofs are not vacuous: hand-over in both directions, a real SPI write frame, a fault clear are reachable; with `DT_W = 2`, a low side (step 55) and a high side (step 104) turn on at the pins after SPI programming, inside the 110-cycle `bmc_dt2` bound. | SymbiYosys |
| Formal mutation | 7 injected bugs must each make a proof or the deep BMC fail. | `scripts/formal_mutants.sh` |
| Simulation | Functional behaviour (counter, duty, shadow timing, SPI, registers) against a cycle-accurate Python model written from the spec; every output compared every cycle. Directed + constrained-random tests, pin-level checkers. | cocotb + Icarus |
| Functional coverage | 39 bins (period, duty and dead-time ranges, hand-overs, swallowed pulses, fault timing, HOLD updates, aborted SPI frames, register reads). Sampled by the scoreboard from what the design did, not from what a test intended; the regression fails on any empty bin. | cocotb (custom collector) |
| Code coverage | The same regression on Verilator with line, branch and toggle coverage; `make coverage` fails below 100 %. Expression and FSM coverage are not measured. | Verilator + `verilator_coverage` |
| Simulation mutation | 6 functional bugs outside the formal scope must each fail at least one checking test (the coverage-closure test does not count). | `scripts/sim_mutants.sh` |
| Lint | `verilator --lint-only -Wall` clean, no waivers. | Verilator |

Why both: formal gives *guarantees* for the safety properties (a sim can only sample
them), simulation checks the *function* (duty, period, register map), which is awkward
to state as properties and is easy to get subtly wrong.

## 5. Implementation flow

LibreLane (OpenROAD-based) on the IHP SG13G2 open PDK, standard cell library
`sg13g2_stdcell`, hardened as a macro (no pad ring). Signoff steps inside the flow:
multi-corner STA (OpenROAD/OpenSTA), KLayout DRC with the IHP rule deck, Netgen LVS
against the synthesised netlist. See `flow/config.json` and `scripts/run_flow.sh`.

**Constraints** ([flow/pwm3_top.sdc](flow/pwm3_top.sdc)) are used for both place-and-route
and signoff. The values are the LibreLane defaults for SG13G2, written out so they are
reviewable: 10 ns clock, 0.25 ns uncertainty (setup and hold), 0.15 ns clock transition,
flat +/-5 % derate, 20 % input and output delay, `sg13g2_buf_4` driving cell, 6 fF load.
All non-clock inputs are asynchronous and feed only the first flop of a synchroniser,
so there is no clock-domain crossing to constrain. I kept an input delay on them instead
of a false path because it keeps the pin-to-synchroniser wires short and bounds the
skew between SCLK, MOSI and CS. All outputs come from flops.

**Corners.** STA runs at the three SG13G2 library corners `typ_1p20V_25C`,
`slow_1p08V_125C` and `fast_1p32V_m40C`, each with nominal RC extraction (`nom_` prefix):
the PDK ships one OpenRCX rule set, so there are no RC-best/RC-worst corners.

### 5.1 Timing closure: two iterations

Both runs use the same 10 ns constraint and the same constraint values (0.25 ns clock
uncertainty, 5 % derating, 20 % I/O delay) and area-oriented synthesis. Iteration 1
used LibreLane's generated SDC; the final run uses the identical values from
`flow/pwm3_top.sdc`.

| | Iteration 1 | Iteration 2 |
|---|---|---|
| RTL change | none | registered `at_zero_q` replaces `cnt == 0` comparator |
| Setup WS, slow corner (1.08 V, 125 °C) | +0.143 ns | +1.158 ns |
| Setup WS, typical (1.20 V, 25 °C) | +3.671 ns | +4.328 ns |
| Setup WS, fast (1.32 V, −40 °C) | +5.780 ns | +6.172 ns |
| Hold WS (worst, fast corner) | +0.107 ns | +0.107 ns |

Evidence: `results/impl_iter1_baseline/` (iteration 1) and `results/impl/sta/` (iteration 2).

**Iteration 1 critical path**
([results/impl_iter1_baseline/critical_path_slow_corner.rpt](results/impl_iter1_baseline/critical_path_slow_corner.rpt)):
`cnt[8]` → 16-bit zero detect (nor4/and3/nand3) → `load` → a 4-stage buffer tree, because
`load` drives the select of about 80 shadow-register muxes → `per_e` mux → period compare
→ counter next-state → `cnt` flop. That is 9.89 ns of arrival at the slow corner.

**Fix.** The counter only ever *loads* the value 0 in two branches of its next-state
logic, and every other branch provably loads a non-zero value: `per_e ≥ 1`,
`cnt+1 < per_e`, or `cnt-1 ≥ 1`. So "counter is zero next cycle" is known for free one
cycle early, and the comparator becomes a flop. The equivalence
`at_zero_q == (cnt_o == 0)` is asserted in `pwm_timebase.v` and proven by k-induction
in the top-level formal task. The cycle-accurate model and all simulation tests are
unchanged and still pass, which is the expected result for a change that preserves
behaviour.

Iteration 2's critical path at the slow corner (8.87 ns arrival,
[results/impl/sta/nom_slow_1p08V_125C/max.rpt](results/impl/sta/nom_slow_1p08V_125C/max.rpt))
now starts at the `at_zero_q` flop itself, and still goes through the `load` fanout tree
and the period compare. 0.66 ns of it is a hold delay cell (`hold480`,
`sg13g2_dlygate4sd3_1`) that the resizer put directly on the `at_zero_q` output, where it
delays every fanout branch, to fix a short flop-to-flop branch at the fast corner. The
next steps, if more speed were needed: keep hold fixing off that net (or fix hold only
on the short branch), and shrink the `load` fanout, for example by duplicating the zero
flag per register group.

Not done, because it isn't needed at 100 MHz: delay-oriented synthesis, retiming,
precomputing `PERIOD−1`.

### 5.2 Hold buffers

The resizer inserts 413 hold buffers; all timing-repair buffers together (574) take
7,913 µm², 22 % of the standard-cell area (`results/impl/metrics.json`). The cause is
the constraint set: the 0.25 ns clock uncertainty applies to hold as well as setup, the
placement resizer adds a 0.1 ns hold margin, and hold is checked at the fast corner.
Many paths here are direct flop-to-flop: shadow registers, synchronisers, the SPI shift
register. With a separately
characterised hold uncertainty (e.g. 0.05 ns) most of these buffers would go away. I
kept the conservative default and report the cost rather than tuning the constraints
to make the numbers look better.

## 6. What is deliberately not here

- High-resolution (sub-cycle) PWM. It would need a calibrated delay line (an analog or
  mixed-signal block), which is out of scope for a digital-only project.
- Trip-zone style per-phase fault actions, cycle-by-cycle current limit, ADC trigger
  offset register. These are straightforward extensions of the same structure.
- Bootstrap refresh at 100 % duty (a real high-side bootstrap driver cannot hold the
  high side on forever); software must limit the duty, or a minimum off-time feature
  could be added.
