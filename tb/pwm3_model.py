"""Cycle-accurate Python reference model of pwm3_top (SPEC.md sections 3-8).

The model is written from the specification, not from the RTL. It covers
everything except the SPI serialiser: register writes enter the model as
(addr, data) transactions at the cycle in which the bus write strobe fires,
and the SPI slave itself is checked separately by read-back tests.

Usage: call step() once per clock edge with the inputs as they were during
the cycle *before* that edge; the returned Outputs are the pin values in the
cycle after the edge.
"""

from __future__ import annotations

from dataclasses import dataclass, field

CNT_W = 16
DT_W = 10
CNT_MASK = (1 << CNT_W) - 1
DT_MAX = (1 << DT_W) - 1

A_CTRL, A_STATUS, A_PERIOD, A_CMPA, A_CMPB, A_CMPC, A_DEADTIME, A_CNT, A_ID = (
    0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0xF)
ID_VALUE = 0x5033
FAULT_LATENCY = 3  # SPEC section 8


@dataclass
class Outputs:
    h: tuple[int, int, int]
    l: tuple[int, int, int]
    sync: int


@dataclass
class _Phase:
    h: int = 0
    l: int = 0
    off_run: int = 0  # consecutive both-off cycles incl. the current one, saturating

    def step(self, rst: bool, safe: bool, ref: int, dt: int) -> None:
        if rst:
            self.h = self.l = self.off_run = 0
            return
        dt_eff = max(dt, 1)
        gap_ok = (not self.h) and (not self.l) and self.off_run >= dt_eff
        if safe:
            h, l = 0, 0
        elif ref:
            h, l = int(self.h or gap_ok), 0
        else:
            h, l = 0, int(self.l or gap_ok)
        self.off_run = 0 if (h or l) else min(self.off_run + 1, DT_MAX)
        self.h, self.l = h, l


@dataclass
class Pwm3Model:
    # synchronisers (value of the 2nd flop is what the logic sees)
    rst_meta: int = 0
    rst_sync: int = 0
    flt_meta: int = 0
    flt_sync: int = 0
    # software registers (pending)
    en: int = 0
    outen: int = 0
    hold: int = 0
    fclr: int = 0
    per: int = 0
    cmp: list[int] = field(default_factory=lambda: [0, 0, 0])
    dt: int = DT_MAX
    # fault latch
    latched: int = 0
    # time base (active / shadow registers)
    per_act: int = 0
    cmp_act: list[int] = field(default_factory=lambda: [0, 0, 0])
    dt_act: int = DT_MAX
    cnt: int = 0
    down: int = 0
    ref: list[int] = field(default_factory=lambda: [0, 0, 0])
    sync: int = 0
    phases: list[_Phase] = field(default_factory=lambda: [_Phase(), _Phase(), _Phase()])

    # ------------------------------------------------------------------ helpers
    @property
    def rst(self) -> bool:
        return not self.rst_sync

    @property
    def safe(self) -> bool:
        return bool(self.flt_sync or self.latched or not self.outen)

    def outputs(self) -> Outputs:
        return Outputs(tuple(p.h for p in self.phases), tuple(p.l for p in self.phases),
                       self.sync)

    @staticmethod
    def reference(cnt: int, down: int, c: int) -> int:
        """SPEC 5: up -> cnt < C, down -> cnt <= C."""
        return int(cnt <= c) if down else int(cnt < c)

    def read(self, addr: int) -> int:
        """Value a register read returns in the current cycle."""
        if addr == A_CTRL:
            return self.en | self.outen << 1 | self.hold << 2
        if addr == A_STATUS:
            return self.latched | self.flt_sync << 1 | self.down << 2 | int(self.safe) << 3
        if addr == A_PERIOD:
            return self.per
        if A_CMPA <= addr <= A_CMPC:
            return self.cmp[addr - A_CMPA]
        if addr == A_DEADTIME:
            return self.dt
        if addr == A_CNT:
            return self.cnt
        if addr == A_ID:
            return ID_VALUE
        return 0

    # --------------------------------------------------------------------- step
    def step(self, rst_ni: int, fault_i: int, wr: int = 0, waddr: int = 0,
             wdata: int = 0) -> Outputs:
        rst = self.rst
        safe = self.safe
        flt = self.flt_sync

        # time base (uses this cycle's register values)
        load = (not self.hold) and ((not self.en) or self.cnt == 0)
        per_e = self.per if load else self.per_act
        cmp_e = list(self.cmp) if load else list(self.cmp_act)
        dt_e = self.dt if load else self.dt_act

        if rst:
            n_per_act, n_cmp_act, n_dt_act = 0, [0, 0, 0], DT_MAX
            n_cnt, n_down, n_ref, n_sync = 0, 0, [0, 0, 0], 0
        else:
            n_per_act, n_cmp_act, n_dt_act = per_e, cmp_e, dt_e
            if not self.en or per_e == 0:
                n_cnt, n_down = 0, 0
            elif not self.down:
                if self.cnt >= per_e - 1:
                    n_cnt, n_down = per_e, 1
                else:
                    n_cnt, n_down = self.cnt + 1, 0
            else:
                if self.cnt <= 1:
                    n_cnt, n_down = 0, 0
                else:
                    n_cnt, n_down = self.cnt - 1, 1
            if self.en:
                n_ref = [self.reference(self.cnt, self.down, c) for c in cmp_e]
            else:
                n_ref = [0, 0, 0]
            n_sync = int(self.en and self.cnt == 0)

        # dead-time units (use this cycle's ref / dt_act / safe)
        for i, ph in enumerate(self.phases):
            ph.step(rst, safe, self.ref[i], self.dt_act)

        # fault latch
        if rst:
            n_latched = 0
        elif flt:
            n_latched = 1
        elif self.fclr:
            n_latched = 0
        else:
            n_latched = self.latched

        # register file
        if rst:
            self.en = self.outen = self.hold = self.fclr = 0
            self.per, self.cmp, self.dt = 0, [0, 0, 0], DT_MAX
        else:
            self.fclr = 0
            if wr:
                if waddr == A_CTRL:
                    self.en, self.outen = wdata & 1, (wdata >> 1) & 1
                    self.hold, self.fclr = (wdata >> 2) & 1, (wdata >> 3) & 1
                elif waddr == A_PERIOD:
                    self.per = wdata & CNT_MASK
                elif A_CMPA <= waddr <= A_CMPC:
                    self.cmp[waddr - A_CMPA] = wdata & CNT_MASK
                elif waddr == A_DEADTIME:
                    self.dt = wdata & DT_MAX

        self.latched = n_latched
        self.per_act, self.cmp_act, self.dt_act = n_per_act, n_cmp_act, n_dt_act
        self.cnt, self.down, self.ref, self.sync = n_cnt, n_down, n_ref, n_sync

        # synchronisers last (their old value was used above)
        self.rst_sync, self.rst_meta = self.rst_meta, int(rst_ni)
        self.flt_sync, self.flt_meta = self.flt_meta, int(fault_i)
        return self.outputs()


def expected_duty(per: int, cmp: int) -> float:
    """Ideal high-side reference duty for compare `cmp` and period `per` (SPEC 5)."""
    if per == 0:
        return 0.0
    return min(cmp, per) / per
