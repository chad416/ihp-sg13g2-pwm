# SPEC — `pwm3_top`: 3-phase centre-aligned PWM with dead-time insertion

Revision 1.0 · status: frozen for implementation

This document is the contract the RTL, the reference model, the testbench and the
formal properties are all written against. If the RTL and this spec disagree, the RTL
is wrong.

## 1. Purpose

Generate the six gate-drive signals (high-side + low-side for phases A, B, C) of a
three-phase two-level inverter, as used for BLDC/PMSM servo drives. The block must make
shoot-through impossible by construction, enforce a programmable minimum dead time,
and react to a hardware fault within a bounded, documented number of clock cycles.

## 2. Parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `CNT_W`   | 16      | Counter / period / compare width |
| `DT_W`    | 10      | Dead-time register width (cycles) |

## 3. Clocking and reset

- Single clock `clk_i`. Implementation target **100 MHz** (10 ns); see DESIGN.md §2 for
  the justification. Everything is on the rising edge.
- `rst_ni`: active-low reset, may be asynchronous to `clk_i` on the board. It is passed
  through a 2-flop synchroniser and then used as a **synchronous** reset everywhere.
  Hold it low for at least 4 clock cycles.
- No other clocks. The SPI interface is *oversampled* in the `clk_i` domain (no SPI clock
  domain exists in the design).

## 4. Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_i` | in | 1 | System clock |
| `rst_ni` | in | 1 | Reset, active low (asynchronous source, synchronised inside) |
| `spi_sclk_i` | in | 1 | SPI clock, mode 0 (CPOL=0, CPHA=0) |
| `spi_cs_ni` | in | 1 | SPI chip select, active low |
| `spi_mosi_i` | in | 1 | SPI data in |
| `spi_miso_o` | out | 1 | SPI data out (driven 0 when not reading) |
| `spi_miso_oe_o` | out | 1 | MISO output enable (= CS active), for an external tri-state pad |
| `fault_i` | in | 1 | Fault / shutdown request, active high, asynchronous |
| `pwm_h_o[2:0]` | out | 3 | High-side gate commands, phase A=0, B=1, C=2, active high |
| `pwm_l_o[2:0]` | out | 3 | Low-side gate commands, active high |
| `sync_o` | out | 1 | One-cycle pulse when the counter is at zero (period valley), for ADC triggering |

All inputs except `clk_i` are treated as asynchronous and pass through 2-flop
synchronisers. All outputs come directly from flip-flops (no combinational logic
between a flop and an output pin), so the gate-drive outputs cannot glitch.

## 5. Counter and PWM reference

- Up/down counter `CNT` with active period `P` (from shadow register).
- Sequence for `P >= 1`: `0, 1, …, P-1` counting **up**, then `P, P-1, …, 1` counting
  **down**, then back to `0`. One PWM period is therefore exactly `2·P` clock cycles:
  `f_PWM = f_clk / (2·P)`.
- `P = 0`: counter holds at 0.
- `CTRL.EN = 0`: counter is held at 0, direction up.
- Per-phase reference (internal, before dead time), with active compare `C`:
  - counting up: `ref = (CNT < C)`
  - counting down: `ref = (CNT <= C)`
  - This gives a high time of exactly `2·C` cycles per period, centred on the valley
    (`CNT = 0`): duty = `C / P`. `C = 0` → 0 %, `C >= P` → 100 %.
- The reference is registered (one cycle after `CNT`).

## 6. Shadow registers (glitch-free update)

- `PERIOD`, `CMPA`, `CMPB`, `CMPC`, `DEADTIME` are written by software into *pending*
  registers. The *active* copies used by the hardware are loaded from the pending ones
  on the clock edge at the end of the cycle in which `CNT = 0` (the valley), and
  continuously while `CTRL.EN = 0`.
- `CTRL.HOLD = 1` inhibits the transfer, so software can update all three phases and
  the period atomically: set HOLD, write registers, clear HOLD.
- Consequence: an update can never create an extra edge within a period; the pulse that
  is centred on the valley is formed from the old compare on its left half and the new
  compare on its right half (standard "load on zero" behaviour).

## 7. Dead-time insertion

Per phase, with active dead time `DT` (cycles) and `DT_eff = max(DT, 1)`:

- **Turn-off is immediate**: when the reference says a switch must be off it turns off
  on the next clock edge.
- **Turn-on is delayed**: a switch may turn on only if *both* outputs of that phase have
  been off for at least `DT_eff` consecutive cycles. The opposite switch must be off.
- Consequences (all formally proven, see §10):
  1. `pwm_h_o[i]` and `pwm_l_o[i]` are never both 1.
  2. Between one switch of a phase turning off and the other one turning on there are
     at least `DT_eff` cycles where both are off.
  3. A reference pulse shorter than `DT_eff` is swallowed (the switch never turns on),
     never shortened below the dead time.
  4. After reset, or after leaving the safe state, the outputs stay off for at least
     `DT_eff` cycles before any switch turns on.
- `DT = 0` is clamped to 1 cycle: hardware never allows a 0-cycle (same-edge)
  hand-over between the high-side and the low-side.
- Reset value of `DEADTIME` is the maximum (`2^DT_W - 1` = 1023 cycles = 10.23 µs at
  100 MHz): an unprogrammed device is as safe as possible.

## 8. Fault / safe state

- `SAFE = fault_sync | FAULT_LATCHED | ~CTRL.OUTEN`.
- `FAULT_LATCHED` is set when the synchronised `fault_i` is 1. It is cleared only by
  writing `CTRL.FCLR = 1` while the synchronised fault is 0.
- In `SAFE` all six outputs are 0 (both switches off — the safe state for a
  two-level inverter with a freewheeling motor).
- **Latency `N = 3` clock cycles**: if `fault_i` is 1 when sampled at clock edge *k*,
  all outputs are 0 from clock edge *k+2* onwards and stay 0 while the fault is latched
  (2 synchroniser flops + 1 output flop; formally proven).
- `fault_i` must be held for at least 2 clock cycles to be guaranteed to be seen
  (shorter pulses may be filtered by the synchroniser). Over-current protection that
  must be faster than this belongs in the analog gate driver (see DESIGN.md §6).

## 9. Register interface — SPI slave, mode 0

- Frame: CS low, 24 bits MSB first, CS high.
  - bit 23: `1` = write, `0` = read
  - bits 22:16: address (only bits 19:16 decoded; 4-bit address space)
  - bits 15:0: write data (write) / don't care (read)
- Write: performed when the 24th bit has been received.
- Read: read data for the address is captured after bit 16 (the 8th) and shifted out
  MSB first on MISO during bits 15:0. MISO changes after SCLK falling edges.
- CS high at any time aborts the frame; nothing is written.
- Because SPI is oversampled through 2-flop synchronisers, `f_SCLK <= f_clk / 10`
  (10 MHz at 100 MHz) and SCLK high/low times must each be >= 4 clock cycles.

### Register map (16-bit)

| Addr | Name | Access | Reset | Fields |
|------|------|--------|-------|--------|
| 0x0 | CTRL | RW | 0x0000 | [0] EN — run counter · [1] OUTEN — enable outputs · [2] HOLD — inhibit shadow transfer · [3] FCLR — write 1 to clear latched fault (self-clearing, reads 0) |
| 0x1 | STATUS | RO | — | [0] FAULT_LATCHED · [1] FAULT_IN (synchronised) · [2] DIR (1 = down) · [3] SAFE |
| 0x2 | PERIOD | RW | 0x0000 | pending period `P` |
| 0x3 | CMPA | RW | 0x0000 | pending compare phase A |
| 0x4 | CMPB | RW | 0x0000 | pending compare phase B |
| 0x5 | CMPC | RW | 0x0000 | pending compare phase C |
| 0x6 | DEADTIME | RW | 0x03FF | [DT_W-1:0] pending dead time (cycles) |
| 0x7 | CNT | RO | — | current counter value |
| 0xF | ID | RO | 0x5033 | constant identifier |
| others | — | RO | 0x0000 | reads 0, writes ignored |

Reads of PERIOD/CMPx/DEADTIME return the *pending* (software-written) value.

## 10. Verification requirements

| ID | Requirement | Method |
|----|-------------|--------|
| V1 | `pwm_h_o[i] & pwm_l_o[i]` is never 1 | formal (k-induction, unbounded) |
| V2 | Every turn-on is preceded by >= `DT_eff` both-off cycles | formal (unbounded) + sim |
| V3 | Fault → all outputs 0 within N = 3 cycles, held while latched | formal (unbounded) + sim |
| V4 | Counter sequence, period and duty match §5 | sim vs. Python reference model |
| V5 | Shadow transfer only at the valley / while disabled, HOLD respected | sim vs. model |
| V6 | SPI register read/write, all registers, aborted frames | sim |
| V7 | Randomised period/duty/dead-time, fault injection, functional coverage closed | sim |
| V8 | Lint clean (Verilator `--lint-only -Wall`) | lint |
