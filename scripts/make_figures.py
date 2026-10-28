"""Generate the README figures / screenshots from real tool output.

Waveforms come from the per-cycle pin traces recorded by the cocotb scoreboard
(results/sim/traces/*.csv); the "terminal" captures are the committed report
files rendered as images. Nothing is drawn by hand.

Usage: python3 scripts/make_figures.py   (from the repository root)
"""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)
T_CLK_NS = 10.0
PH = "ABC"
C_H, C_L, C_X = "#1f6fb4", "#c8551b", "#6b6b6b"


def load(name: str) -> dict[str, list[int]]:
    with open(ROOT / "results" / "sim" / "traces" / f"{name}.csv") as f:
        rows = list(csv.DictReader(f))
    return {k: [int(r[k]) for r in rows] for k in rows[0]}


def digital(ax, t, y, base, color, label):
    ax.step(t, [base + 0.8 * v for v in y], where="post", color=color, lw=1.4)
    ax.text(t[0] - (t[-1] - t[0]) * 0.01, base + 0.4, label, ha="right", va="center",
            fontsize=9, color=color)


def fig_three_phase() -> None:
    d = load("basic_pwm")
    t = [(c - d["cycle"][0]) * T_CLK_NS / 1000 for c in d["cycle"]]  # us
    fig, (a0, a1) = plt.subplots(2, 1, figsize=(11, 6.2), sharex=True,
                                 gridspec_kw={"height_ratios": [1, 2.6]})
    a0.plot(t, d["cnt"], color=C_X, lw=1.2)
    a0.set_ylabel("counter")
    a0.set_title("3-phase centre-aligned PWM, cocotb simulation of pwm3_top "
                 "(PERIOD=100, CMP A/B/C = 25/50/90, DT = 7 cycles, f_clk = 100 MHz)",
                 fontsize=10)
    for k, s in enumerate(d["sync"]):
        if s:
            a0.axvline(t[k], color="#999999", lw=0.6, ls=":")
    for i, p in enumerate(PH):
        base = (2 - i) * 2.2
        digital(a1, t, d[f"h_{p.lower()}"], base + 1.0, C_H, f"{p} high")
        digital(a1, t, d[f"l_{p.lower()}"], base, C_L, f"{p} low")
    a1.set_yticks([])
    a1.set_xlabel("time [µs]")
    a1.set_xlim(t[0], t[-1])
    for a in (a0, a1):
        a.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(OUT / "sim_pwm_3phase.png", dpi=150)
    plt.close(fig)


def fig_deadtime_zoom() -> None:
    d = load("basic_pwm")
    h, l = d["h_a"], d["l_a"]
    # first low->high hand-over of phase A in the trace
    k_on = next(k for k in range(1, len(h)) if h[k] and not h[k - 1])
    k_off = max(k for k in range(k_on) if l[k - 1] and not l[k])
    gap = k_on - k_off
    lo, hi = max(0, k_off - 12), min(len(h), k_on + 12)
    t = [c - d["cycle"][lo] for c in d["cycle"][lo:hi]]
    fig, ax = plt.subplots(figsize=(9, 3.4))
    digital(ax, t, l[lo:hi], 0.0, C_L, "A low ")
    digital(ax, t, h[lo:hi], 1.8, C_H, "A high ")
    x0, x1 = k_off - lo, k_on - lo
    ax.annotate("", xy=(x1, 1.2), xytext=(x0, 1.2),
                arrowprops=dict(arrowstyle="<->", color="black", lw=1))
    ax.text((x0 + x1) / 2, 1.28, f"both off: {gap} cycles = {gap * T_CLK_NS:.0f} ns "
            f"(DEADTIME = 7)", ha="center", va="bottom", fontsize=9)
    ax.set_yticks([])
    ax.set_xlabel("clock cycles (10 ns)")
    ax.set_title("Dead-time hand-over, phase A low → high (measured from the simulated pins)",
                 fontsize=10)
    ax.spines[["top", "right", "left"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(OUT / "sim_deadtime_zoom.png", dpi=150)
    plt.close(fig)


def fig_fault() -> None:
    d = load("fault_response")
    f = d["fault_i"]
    k_f = next(k for k in range(len(f)) if f[k])
    any_on = [max(d[f"{s}_{p}"][k] for s in "hl" for p in "abc") for k in range(len(f))]
    k_off = next(k for k in range(k_f, len(f)) if not any_on[k])
    t = [c - d["cycle"][k_f] for c in d["cycle"]]
    fig, ax = plt.subplots(figsize=(9, 4.2))
    digital(ax, t, f, 7.2, "#a00000", "fault_i ")
    for i, p in enumerate(PH):
        base = (2 - i) * 2.2
        digital(ax, t, d[f"h_{p.lower()}"], base + 1.0, C_H, f"{p} high ")
        digital(ax, t, d[f"l_{p.lower()}"], base, C_L, f"{p} low ")
    ax.axvline(0, color="#a00000", lw=0.8, ls=":")
    ax.axvline(t[k_off], color="black", lw=0.8, ls=":")
    n_edges = k_off - k_f + 1
    ax.text(0.01, 0.99, f"edge k = 0 first samples fault_i = 1; all six outputs are off after "
            f"edge k+{k_off - k_f}, i.e. {n_edges} clock edges (spec and formal proof: N = 3)",
            transform=ax.transAxes, fontsize=9, va="top")
    ax.set_ylim(-0.3, 8.9)
    ax.set_yticks([])
    ax.set_xlabel("clock edges relative to the first edge that samples fault_i = 1")
    ax.set_title("Fault shutdown: 2-cycle fault pulse, outputs stay off because the fault is latched",
                 fontsize=10)
    ax.spines[["top", "right", "left"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(OUT / "sim_fault_response.png", dpi=150)
    plt.close(fig)


def terminal(name: str, title: str, files: list[tuple[str, str]], max_lines: int = 60) -> None:
    """Render report files as a terminal-style image (text copied verbatim)."""
    lines = [f"$ {title}"]
    for label, rel in files:
        lines.append("")
        lines.append(f"$ cat {rel}" if not label else f"$ {label}")
        text = (ROOT / rel).read_text(encoding="utf-8", errors="replace").splitlines()
        lines += text[:max_lines]
    width = max(len(s) for s in lines)
    fig = plt.figure(figsize=(max(8, width * 0.075), 0.19 * len(lines) + 0.6))
    fig.patch.set_facecolor("#1e1e1e")
    fig.text(0.01, 0.99, "\n".join(lines), family="DejaVu Sans Mono", fontsize=8.5,
             color="#d4d4d4", va="top", ha="left")
    fig.savefig(OUT / name, dpi=140, facecolor=fig.get_facecolor())
    plt.close(fig)


def main() -> None:
    fig_three_phase()
    fig_deadtime_zoom()
    fig_fault()
    terminal("term_formal.png", "make formal   # SymbiYosys results + mutation check",
             [("", "results/formal/summary.txt"), ("", "results/formal/mutation.txt")])
    terminal("term_sim.png", "make sim   # cocotb regression, coverage, mutation check",
             [("", "results/sim/summary.txt"), ("", "results/sim/mutation.txt")])
    terminal("term_coverage.png", "functional coverage report",
             [("", "results/sim/coverage_report.txt")], max_lines=70)
    terminal("term_sta_signoff.png", "make flow && make results   # post-route multi-corner STA + signoff",
             [("", "results/impl/sta/summary.rpt"), ("", "results/impl/summary.md")])
    terminal("term_lvs.png", "Netgen LVS (tail of the report)",
             [("tail -n 25 results/impl/lvs_netgen/lvs.netgen.rpt", "results/impl/lvs_netgen/lvs_tail.txt")])
    print("figures written to", OUT)


if __name__ == "__main__":
    main()
