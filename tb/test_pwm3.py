"""cocotb testbench for pwm3_top.

Structure
  * SpiMaster   -- bit-banged SPI mode-0 master on the real pins (f_SCLK = f_clk/10).
  * Scoreboard  -- steps the Python reference model (pwm3_model.py) every clock
                   and compares all 7 outputs cycle by cycle. Register writes reach
                   the model from the DUT's internal bus strobe; the SPI shifter is
                   verified separately by read-back.
  * Pin checkers (independent of the model): no high/low overlap, dead time >=
                   programmed value, fault latency <= 3 cycles.
  * Coverage    -- functional coverage bins; the last test fails if any bin is empty.
                   Configuration and event bins are sampled by the scoreboard from
                   what the design actually did (active shadow registers, fault
                   latch, output pins, SPI bit counter), not from what a test meant
                   to do. Only the spi_read bins are sampled on the stimulus side;
                   the read-back of every register is asserted in a directed test.
"""

from __future__ import annotations

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from pwm3_model import (A_CMPA, A_CMPB, A_CMPC, A_CNT, A_CTRL, A_DEADTIME, A_ID,
                        A_PERIOD, A_STATUS, DT_MAX, FAULT_LATENCY, ID_VALUE,
                        Pwm3Model)

CLK_NS = 10
SPI_HALF = 5  # clk cycles per SCLK half period -> f_SCLK = f_clk / 10 (SPEC 9)
SEED = int(os.environ.get("PWM3_SEED", "20261028"))

CTRL_EN, CTRL_OUTEN, CTRL_HOLD, CTRL_FCLR = 1, 2, 4, 8


# ============================================================================ coverage
class Coverage:
    """Minimal functional-coverage collector (named bins with hit counts)."""

    BINS = {
        "period": ["0", "1", "2-15", "16-255", "256-4095", ">=4096"],
        "duty": ["0%", "(0,25%]", "(25,50%]", "(50,75%]", "(75,100%)", "100%"],
        "deadtime": ["0 (clamped)", "1", "2-15", "16-255", "256-1022", "1023"],
        "event": [
            "handover low->high", "handover high->low", "pulse swallowed by dead time",
            "fault while high side on", "fault while low side on",
            "fault during dead time", "fault clear blocked (fault still active)",
            "fault cleared by software", "atomic multi-register update (HOLD)",
            "compare update while running", "counter disabled mid-period",
            "spi frame aborted",
        ],
        "spi_read": [f"0x{a:X}" for a in (A_CTRL, A_STATUS, A_PERIOD, A_CMPA, A_CMPB,
                                          A_CMPC, A_DEADTIME, A_CNT, A_ID)],
    }

    def __init__(self) -> None:
        self.hits = {g: {b: 0 for b in bins} for g, bins in self.BINS.items()}

    def hit(self, group: str, name: str) -> None:
        self.hits[group][name] += 1

    def sample_config(self, per: int, cmps: list[int], dt: int) -> None:
        self.hit("period", "0" if per == 0 else "1" if per == 1 else
                 "2-15" if per < 16 else "16-255" if per < 256 else
                 "256-4095" if per < 4096 else ">=4096")
        for c in cmps:
            if c == 0 or per == 0:
                b = "0%"
            elif c >= per:
                b = "100%"
            else:
                d = c / per
                b = ("(0,25%]" if d <= 0.25 else "(25,50%]" if d <= 0.5 else
                     "(50,75%]" if d <= 0.75 else "(75,100%)")
            self.hit("duty", b)
        self.hit("deadtime", "0 (clamped)" if dt == 0 else "1" if dt == 1 else
                 "2-15" if dt < 16 else "16-255" if dt < 256 else
                 "256-1022" if dt < DT_MAX else "1023")

    def holes(self) -> list[str]:
        return [f"{g}:{b}" for g, bins in self.hits.items() for b, n in bins.items() if n == 0]

    def report(self) -> str:
        lines = ["Functional coverage report (pwm3_top)", "=" * 38]
        total = covered = 0
        for g, bins in self.hits.items():
            lines.append(f"\n[{g}]")
            for b, n in bins.items():
                total += 1
                covered += n > 0
                lines.append(f"  {'HIT ' if n else 'MISS'} {b:<45} {n:>8}")
        lines.append(f"\nBins covered: {covered}/{total} ({100.0 * covered / total:.1f} %)")
        return "\n".join(lines)


COV = Coverage()


# ============================================================================ SPI master
class SpiMaster:
    def __init__(self, dut) -> None:
        self.dut = dut
        dut.spi_cs_ni.value = 1
        dut.spi_sclk_i.value = 0
        dut.spi_mosi_i.value = 0

    async def _half(self) -> None:
        await ClockCycles(self.dut.clk_i, SPI_HALF, rising=False)

    async def xfer(self, write: bool, addr: int, data: int = 0, abort_after: int | None = None) -> int:
        """One 24-bit frame. Returns the 16 bits read on MISO during the data phase."""
        dut = self.dut
        frame = (int(write) << 23) | ((addr & 0x7F) << 16) | (data & 0xFFFF)
        await FallingEdge(dut.clk_i)
        dut.spi_cs_ni.value = 0
        rx = 0
        for n, bit in enumerate(range(23, -1, -1)):
            if abort_after is not None and n == abort_after:
                break
            dut.spi_mosi_i.value = (frame >> bit) & 1
            await self._half()
            if bit < 16:
                rx = (rx << 1) | int(dut.spi_miso_o.value)
            dut.spi_sclk_i.value = 1
            await self._half()
            dut.spi_sclk_i.value = 0
        await self._half()
        dut.spi_cs_ni.value = 1
        await self._half()
        return rx

    async def write(self, addr: int, data: int) -> None:
        await self.xfer(True, addr, data)

    async def read(self, addr: int) -> int:
        key = f"0x{addr:X}"
        if key in COV.hits["spi_read"]:
            COV.hit("spi_read", key)
        return await self.xfer(False, addr)


# ============================================================================ scoreboard
class Scoreboard:
    """Steps the model every clock and checks pins; also runs the pin checkers."""

    def __init__(self, dut) -> None:
        self.dut = dut
        self.model = Pwm3Model()
        self.cycles = 0
        self.errors: list[str] = []
        self.off_run = [0, 0, 0]
        self.fault_hist: list[int] = []
        self.prev_h = [0, 0, 0]
        self.prev_l = [0, 0, 0]
        # per-phase tracking of the current reference-high run (pulse swallowing)
        self.ref_last = [0, 0, 0]
        self.run_saw_h = [False, False, False]
        self.run_tainted = [False, False, False]
        self.trace: list[tuple[int, ...]] = []  # per-cycle pin record for figures
        # coverage sampling state
        self.cfg_key: tuple | None = None
        self.hold_seen = False
        self.spi_prev = (0, 0)  # (cs active, bit count) in the previous cycle
        self._task = None

    def _pins(self) -> tuple[int, int]:
        """Primary inputs. Drivers only change them on falling edges, so the value
        read in ReadOnly after a rising edge is the value that edge sampled."""
        return int(self.dut.rst_ni.value), int(self.dut.fault_i.value)

    def _bus(self) -> tuple[int, int, int]:
        """Internal write strobe (a flop output): the value read after edge k is
        the value present during cycle k, i.e. what edge k+1 acts on."""
        s = self.dut.u_spi
        return int(s.wr_o.value), int(s.waddr_o.value), int(s.wdata_o.value)

    def start(self) -> None:
        self._task = cocotb.start_soon(self._run())

    def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None

    def _err(self, msg: str) -> None:
        if len(self.errors) < 20:
            self.dut._log.error(f"cycle {self.cycles}: {msg}")
        self.errors.append(msg)

    async def _run(self) -> None:
        dut = self.dut
        await ReadOnly()
        bus_prev = self._bus()
        while True:
            await RisingEdge(dut.clk_i)
            await ReadOnly()
            m = self.model
            dt_before = m.dt_act
            before = (m.en, m.cnt, m.fclr, m.flt_sync, m.latched, m.safe)
            pins = self._pins()
            exp = m.step(*pins, *bus_prev)
            self.cycles += 1
            h_v, l_v = int(dut.pwm_h_o.value), int(dut.pwm_l_o.value)
            h = [(h_v >> i) & 1 for i in range(3)]
            l = [(l_v >> i) & 1 for i in range(3)]
            sync = int(dut.sync_o.value)
            self.trace.append((self.cycles, int(dut.u_tb.cnt_o.value), *h, *l, sync, pins[1]))

            # 1. model comparison (all outputs, every cycle)
            if tuple(h) != exp.h or tuple(l) != exp.l or sync != exp.sync:
                self._err(f"model mismatch: h={h} l={l} sync={sync} expected "
                          f"h={list(exp.h)} l={list(exp.l)} sync={exp.sync}")

            # 2. independent pin checkers
            fault_i = pins[1]
            self.fault_hist = (self.fault_hist + [fault_i])[-(FAULT_LATENCY + 1):]
            for i in range(3):
                if h[i] and l[i]:
                    self._err(f"phase {i}: high and low side both on")
                turned_on = (h[i] and not self.prev_h[i]) or (l[i] and not self.prev_l[i])
                if turned_on:
                    if self.off_run[i] < max(dt_before, 1):
                        self._err(f"phase {i}: dead time {self.off_run[i]} < {max(dt_before, 1)}")
                    COV.hit("event", "handover low->high" if h[i] else "handover high->low")
                # pulse swallowing: a reference-high run that ended without the
                # high side ever turning on, while not in the safe state
                if self.ref_last[i]:
                    self.run_saw_h[i] = self.run_saw_h[i] or bool(h[i])
                    self.run_tainted[i] = self.run_tainted[i] or m.safe
                    if not m.ref[i]:
                        if not self.run_saw_h[i] and not self.run_tainted[i]:
                            COV.hit("event", "pulse swallowed by dead time")
                        self.run_saw_h[i] = self.run_tainted[i] = False
                self.ref_last[i] = m.ref[i]
                self.off_run[i] = 0 if (h[i] or l[i]) else self.off_run[i] + 1
            if len(self.fault_hist) > FAULT_LATENCY and self.fault_hist[-FAULT_LATENCY]:
                if any(h) or any(l):
                    self._err(f"outputs not safe {FAULT_LATENCY} cycles after fault_i")
            self.prev_h, self.prev_l = h, l
            self._sample_coverage(before, h, l)
            bus_prev = self._bus()

    def _sample_coverage(self, before: tuple, h: list[int], l: list[int]) -> None:
        """Coverage from observed behaviour; called once per cycle after the model step."""
        m = self.model
        en_b, cnt_b, fclr_b, flt_b, latched_b, safe_b = before
        if m.rst:
            self.cfg_key = None
            return
        # Configuration the counter actually runs with: sampled whenever the active
        # (shadow) registers change while enabled, or when the counter is enabled.
        key = (m.per_act, tuple(m.cmp_act), m.dt_act)
        self.hold_seen = self.hold_seen or bool(m.hold)
        if m.en and (key != self.cfg_key or not en_b):
            COV.sample_config(m.per_act, list(m.cmp_act), m.dt_act)
            if en_b and self.cfg_key is not None:
                old = self.cfg_key
                changed = (int(key[0] != old[0]) + sum(a != b for a, b in zip(key[1], old[1]))
                           + int(key[2] != old[2]))
                if key[1] != old[1]:
                    COV.hit("event", "compare update while running")
                if changed >= 2 and self.hold_seen:
                    COV.hit("event", "atomic multi-register update (HOLD)")
            self.hold_seen = bool(m.hold)
        self.cfg_key = key if m.en else None
        if en_b and not m.en and cnt_b != 0:
            COV.hit("event", "counter disabled mid-period")
        # Fault events: the synchronised fault arrives while the outputs were enabled;
        # h/l are the pins formed just before it took effect.
        if m.flt_sync and not safe_b:
            if any(h):
                COV.hit("event", "fault while high side on")
            if any(l):
                COV.hit("event", "fault while low side on")
            if any(not (h[i] or l[i]) for i in range(3)):
                COV.hit("event", "fault during dead time")
        if fclr_b and flt_b:
            COV.hit("event", "fault clear blocked (fault still active)")
        if latched_b and not m.latched:
            COV.hit("event", "fault cleared by software")
        # SPI: chip select released in the middle of a frame.
        spi = (int(self.dut.u_spi.cs_q.value), int(self.dut.u_spi.bitcnt_q.value))
        if self.spi_prev[0] and not spi[0] and self.spi_prev[1] not in (0, 24):
            COV.hit("event", "spi frame aborted")
        self.spi_prev = spi


# ============================================================================ helpers
async def start(dut) -> tuple[SpiMaster, Scoreboard]:
    Clock(dut.clk_i, CLK_NS, unit="ns").start()  # cocotb >= 2.0
    dut.rst_ni.value = 0
    dut.fault_i.value = 0
    spi = SpiMaster(dut)
    await ClockCycles(dut.clk_i, 6)
    sb = Scoreboard(dut)
    sb.start()
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await ClockCycles(dut.clk_i, 4)
    return spi, sb


def save_trace(sb: Scoreboard, name: str, start: int, stop: int) -> None:
    """Write trace rows [start:stop] of pin activity as CSV (used for README figures)."""
    out = Path(os.environ.get("PWM3_TRACE_DIR", "traces")) / f"{name}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = ["cycle,cnt,h_a,h_b,h_c,l_a,l_b,l_c,sync,fault_i"]
    rows += [",".join(map(str, r)) for r in sb.trace[start:stop]]
    out.write_text("\n".join(rows) + "\n")


def finish(sb: Scoreboard) -> None:
    sb.stop()
    sb.dut._log.info(f"scoreboard: {sb.cycles} cycles compared, {len(sb.errors)} errors")
    assert not sb.errors, f"{len(sb.errors)} errors, first: {sb.errors[0]}"


async def configure(spi: SpiMaster, per: int, cmps: list[int], dt: int, ctrl: int,
                    atomic: bool = False) -> None:
    if atomic:
        await spi.write(A_CTRL, ctrl | CTRL_HOLD)
    await spi.write(A_PERIOD, per)
    for a, c in zip((A_CMPA, A_CMPB, A_CMPC), cmps):
        await spi.write(a, c)
    await spi.write(A_DEADTIME, dt)
    await spi.write(A_CTRL, ctrl)


async def pulse_fault(dut, cycles: int) -> None:
    await FallingEdge(dut.clk_i)
    dut.fault_i.value = 1
    await ClockCycles(dut.clk_i, cycles, rising=False)
    dut.fault_i.value = 0


# ============================================================================ tests
@cocotb.test()
async def test_reset_and_id(dut):
    """Reset values, ID register and safe outputs after reset."""
    spi, sb = await start(dut)
    assert await spi.read(A_ID) == ID_VALUE
    assert await spi.read(A_DEADTIME) == DT_MAX, "dead time must reset to maximum"
    assert await spi.read(A_CTRL) == 0
    status = await spi.read(A_STATUS)
    assert status == 0b1000, f"STATUS after reset = {status:#x} (only SAFE expected)"
    assert int(dut.pwm_h_o.value) == 0 and int(dut.pwm_l_o.value) == 0
    finish(sb)


@cocotb.test()
async def test_register_access(dut):
    """Write/read every RW register, RO registers ignore writes, aborted frames."""
    rng = random.Random(SEED + 1)
    spi, sb = await start(dut)
    for _ in range(4):
        vals = {A_PERIOD: rng.randrange(1 << 16), A_CMPA: rng.randrange(1 << 16),
                A_CMPB: rng.randrange(1 << 16), A_CMPC: rng.randrange(1 << 16),
                A_DEADTIME: rng.randrange(1 << 16)}
        for a, v in vals.items():
            await spi.write(a, v)
        for a, v in vals.items():
            exp = v & DT_MAX if a == A_DEADTIME else v
            got = await spi.read(a)
            assert got == exp, f"reg {a:#x}: read {got:#06x}, expected {exp:#06x}"
    await spi.write(A_CTRL, CTRL_HOLD | CTRL_FCLR)  # FCLR is write-only, reads 0
    assert await spi.read(A_CTRL) == CTRL_HOLD
    await spi.write(A_ID, 0x1234)
    assert await spi.read(A_ID) == ID_VALUE
    await spi.write(A_CNT, 0x1234)
    assert await spi.read(A_CNT) == 0
    assert await spi.read(0x9) == 0
    # aborted frame: CS released after 20 of 24 bits -> no write
    await spi.write(A_CMPA, 0x00AA)
    await spi.xfer(True, A_CMPA, 0x5555, abort_after=20)
    assert await spi.read(A_CMPA) == 0x00AA
    finish(sb)


@cocotb.test()
async def test_basic_pwm(dut):
    """Steady-state waveform: period, duty, centre alignment and dead time on pins."""
    spi, sb = await start(dut)
    per, cmps, dt = 100, [25, 50, 90], 7
    await configure(spi, per, cmps, dt, CTRL_EN | CTRL_OUTEN)
    # let the new values reach the active registers, then measure 3 full periods
    while not int(dut.sync_o.value):
        await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    while not int(dut.sync_o.value):
        await RisingEdge(dut.clk_i)
    h_cnt, l_cnt, n = [0, 0, 0], [0, 0, 0], 0
    for _ in range(3 * 2 * per):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        n += 1
        hv, lv = int(dut.pwm_h_o.value), int(dut.pwm_l_o.value)
        for i in range(3):
            h_cnt[i] += (hv >> i) & 1
            l_cnt[i] += (lv >> i) & 1
    for i, c in enumerate(cmps):
        exp_h = 3 * (2 * c - dt)            # high-side loses one dead time per period
        exp_l = 3 * (2 * (per - c) - dt)    # low-side loses the other one
        assert h_cnt[i] == exp_h, f"phase {i}: high-side on {h_cnt[i]} cycles, expected {exp_h}"
        assert l_cnt[i] == exp_l, f"phase {i}: low-side on {l_cnt[i]} cycles, expected {exp_l}"
        dut._log.info(f"phase {i}: C={c} P={per} DT={dt}: high {h_cnt[i]}/{n} low {l_cnt[i]}/{n}")
    save_trace(sb, "basic_pwm", -n, None)
    finish(sb)


@cocotb.test()
async def test_shadow_and_hold(dut):
    """Writes only take effect at the valley; HOLD makes multi-register updates atomic."""
    spi, sb = await start(dut)
    await configure(spi, 200, [50, 100, 150], 4, CTRL_EN | CTRL_OUTEN)
    await ClockCycles(dut.clk_i, 1000)
    # Non-atomic update while running (model checks the exact load cycle).
    await spi.write(A_CMPA, 120)
    await ClockCycles(dut.clk_i, 600)
    # Atomic update: nothing may change while HOLD=1, even across several valleys.
    await spi.write(A_CTRL, CTRL_EN | CTRL_OUTEN | CTRL_HOLD)
    await spi.write(A_CMPA, 10)
    await spi.write(A_CMPB, 20)
    await spi.write(A_PERIOD, 150)
    await ClockCycles(dut.clk_i, 900)
    assert int(dut.u_tb.cmpa_q.value) == 120 and int(dut.u_tb.per_q.value) == 200, \
        "active registers changed while HOLD was set"
    await spi.write(A_CTRL, CTRL_EN | CTRL_OUTEN)
    await ClockCycles(dut.clk_i, 800)
    assert int(dut.u_tb.cmpa_q.value) == 10 and int(dut.u_tb.per_q.value) == 150
    # Disable the counter while running: outputs go to the low-side state cleanly.
    await spi.write(A_CTRL, CTRL_OUTEN)
    await ClockCycles(dut.clk_i, 300)
    finish(sb)


@cocotb.test()
async def test_fault(dut):
    """Fault latency, latching, blocked clear while active, recovery with dead time."""
    spi, sb = await start(dut)
    await configure(spi, 64, [16, 32, 60], 3, CTRL_EN | CTRL_OUTEN)
    await ClockCycles(dut.clk_i, 500)
    i_fault = len(sb.trace)
    await pulse_fault(dut, 2)  # minimum guaranteed pulse width (SPEC 8)
    await ClockCycles(dut.clk_i, 10)
    save_trace(sb, "fault_response", i_fault - 40, i_fault + 12)
    assert int(dut.pwm_h_o.value) == 0 and int(dut.pwm_l_o.value) == 0
    assert (await spi.read(A_STATUS)) & 1, "fault not latched"
    # Clear while the fault input is still active -> must stay latched.
    await FallingEdge(dut.clk_i)
    dut.fault_i.value = 1
    await spi.write(A_CTRL, CTRL_EN | CTRL_OUTEN | CTRL_FCLR)
    assert (await spi.read(A_STATUS)) & 1
    dut.fault_i.value = 0
    await ClockCycles(dut.clk_i, 20)
    assert (await spi.read(A_STATUS)) & 1, "latch must hold after the fault goes away"
    await spi.write(A_CTRL, CTRL_EN | CTRL_OUTEN | CTRL_FCLR)
    assert (await spi.read(A_STATUS)) & 1 == 0
    await ClockCycles(dut.clk_i, 400)
    assert int(dut.pwm_h_o.value) | int(dut.pwm_l_o.value), "outputs did not recover"
    finish(sb)


@cocotb.test()
async def test_edge_cases(dut):
    """P=0, P=1, C=0, C>=P, DT=0 (clamped to 1), DT longer than the pulse, P = 0xFFFF."""
    spi, sb = await start(dut)
    cases = [
        (0, [0, 5, 0xFFFF], 2, 300),
        (1, [0, 1, 2], 0, 300),
        (2, [1, 1, 1], 0, 300),
        (40, [0, 40, 41], 1, 600),
        (40, [3, 20, 37], 30, 800),       # 2*C-DT < 0 for phase A -> swallowed
        (400, [100, 250, 399], 300, 4 * 400),  # long dead time (IGBT-like 3 us)
        (5000, [1250, 2500, 4999], 1023, 2 * 2 * 5000 + 200),
        (0xFFFF, [1, 0x8000, 0xFFFF], 5, 2 * 0xFFFF + 400),  # full counter range
    ]
    for per, cmps, dt, run in cases:
        await configure(spi, per, cmps, dt, CTRL_EN | CTRL_OUTEN, atomic=True)
        await ClockCycles(dut.clk_i, run)
    finish(sb)


@cocotb.test()
async def test_random(dut):
    """Constrained-random configurations, update timing, HOLD and fault injection."""
    rng = random.Random(SEED)
    n_cfg = int(os.environ.get("PWM3_RANDOM_CFGS", "120"))
    spi, sb = await start(dut)

    def rand_period() -> int:
        return rng.choice([rng.randint(1, 15), rng.randint(16, 255), rng.randint(256, 600)])

    def rand_cmp(per: int) -> int:
        return rng.choice([0, rng.randint(0, per), rng.randint(0, per),
                           per, per + rng.randint(1, 50)]) & 0xFFFF

    def rand_dt(per: int) -> int:
        return rng.choice([0, 1, rng.randint(2, 15), rng.randint(16, 255),
                           rng.randint(2, max(2, per // 2))])

    ctrl = CTRL_EN | CTRL_OUTEN
    for k in range(n_cfg):
        per = rand_period()
        cmps = [rand_cmp(per) for _ in range(3)]
        dt = rand_dt(per)
        atomic = rng.random() < 0.4
        await configure(spi, per, cmps, dt, ctrl, atomic=atomic)
        await ClockCycles(dut.clk_i, rng.randint(2 * per, 6 * per + 50))
        if rng.random() < 0.25:
            await pulse_fault(dut, rng.randint(2, 20))
            await ClockCycles(dut.clk_i, rng.randint(5, 50))
            await spi.write(A_CTRL, ctrl | CTRL_FCLR)
        if rng.random() < 0.05:
            await spi.write(A_CTRL, CTRL_OUTEN)
            await ClockCycles(dut.clk_i, rng.randint(10, 100))
        if k % 10 == 0:
            await spi.read(rng.choice([A_STATUS, A_CNT, A_CTRL]))
    finish(sb)


@cocotb.test()
async def test_zz_coverage_closure(dut):
    """Writes the coverage report and fails on any empty bin (runs last)."""
    report = COV.report()
    out = Path(os.environ.get("PWM3_COV_REPORT", "coverage_report.txt"))
    out.write_text(report + "\n")
    dut._log.info("\n" + report)
    holes = COV.holes()
    assert not holes, f"coverage holes: {holes}"
