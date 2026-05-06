#!/usr/bin/env python3
"""
Render path_x_simple.vcd to a *clear* annotated waveform PNG.

Improvements over render_waveform.py:
- Cycle-by-cycle "i=0..i=15" QPSK pair index labels at the top
- Inline annotations showing the bit pair value at each cycle
- decoded[31:0] shown as a 4-byte block diagram filling left-to-right
- Reset / TX / Capture / Done phase bars
- Bigger fonts, clearer colors, no overlapping text
"""
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np


def parse_vcd(path):
    with open(path) as f:
        lines = f.read().splitlines()

    sig_id = {}
    sig_w = {}
    in_top = False
    depth = 0
    for ln in lines:
        if ln.startswith("$scope"):
            depth += 1; in_top = (depth == 1); continue
        if ln.startswith("$upscope"):
            depth -= 1; in_top = (depth == 1); continue
        if not in_top: continue
        m = re.match(r"\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)", ln)
        if m:
            sig_w[m.group(2)] = int(m.group(1))
            sig_id[m.group(2)] = m.group(3)

    events = {n: [] for n in sig_id.values()}
    cur_t = 0
    for ln in lines:
        if ln.startswith("#"):
            try: cur_t = int(ln[1:])
            except: pass
        elif ln.startswith("b"):
            m = re.match(r"b([01xXzZ]+)\s+(\S+)", ln)
            if m and m.group(2) in sig_id:
                bits = m.group(1).replace('x','0').replace('z','0').replace('X','0').replace('Z','0')
                v = int(bits, 2)
                w = sig_w[m.group(2)]
                if sig_id[m.group(2)] in ('tx_I','tx_Q','rx_I','rx_Q','llr0','llr1'):
                    if v >= (1 << (w-1)): v -= (1 << w)
                events[sig_id[m.group(2)]].append((cur_t, v))
        elif len(ln) >= 2 and ln[0] in '01':
            ch = ln[1:]
            if ch in sig_id:
                events[sig_id[ch]].append((cur_t, int(ln[0])))
    return events


def step_xy(events, t_min, t_max, default=0):
    if not events:
        return [t_min, t_max], [default, default]
    xs = [t_min]
    ys = [default]
    for t, v in events:
        if t < t_min:
            ys[0] = v
            continue
        if t > t_max:
            break
        xs.append(t); ys.append(ys[-1])
        xs.append(t); ys.append(v)
    xs.append(t_max); ys.append(ys[-1])
    return xs, ys


def value_at(events, t, default=0):
    v = default
    for et, ev in events:
        if et <= t: v = ev
        else: break
    return v


def main():
    vcd = "/home/ysara/fpga_hdl/simulation/path_x_simple.vcd"
    ev = parse_vcd(vcd)

    # Window: 0 ... 400 ns covers reset → all 16 QPSK pairs → final
    t0, t1 = 0, 400_000  # picoseconds

    fig = plt.figure(figsize=(18, 12))
    gs = fig.add_gridspec(7, 1, hspace=0.05,
                          height_ratios=[0.7, 0.7, 1.4, 1.4, 1.4, 1.4, 2.0])

    # Per-cycle pair labels along top axis (every 10 ns from 155 to 305)
    ax_top = fig.add_subplot(gs[0])
    ax_top.set_xlim(t0, t1)
    ax_top.set_ylim(0, 1)
    ax_top.set_yticks([])
    ax_top.set_xticks([])
    for spine in ax_top.spines.values(): spine.set_visible(False)
    # Reset / TX / Capture / Done phase bars
    ax_top.add_patch(patches.Rectangle((0, 0.0), 95_000, 1, color="#FFE0E0", alpha=0.6))
    ax_top.text(47_500, 0.5, "RESET", ha="center", va="center", fontsize=10, color="#A00", weight="bold")
    ax_top.add_patch(patches.Rectangle((95_000, 0.0), 60_000, 1, color="#FFF5DA", alpha=0.6))
    ax_top.text(125_000, 0.5, "warm-up", ha="center", va="center", fontsize=9, color="#770")
    ax_top.add_patch(patches.Rectangle((155_000, 0.0), 160_000, 1, color="#E0F0FF", alpha=0.6))
    ax_top.text(235_000, 0.5, "TX 16 QPSK pairs (i=0…15)", ha="center", va="center", fontsize=10, color="#005", weight="bold")
    ax_top.add_patch(patches.Rectangle((315_000, 0.0), 85_000, 1, color="#E0FFE0", alpha=0.6))
    ax_top.text(357_500, 0.5, "FLUSH / DONE", ha="center", va="center", fontsize=10, color="#070", weight="bold")

    # Index labels under phase bar
    ax_idx = fig.add_subplot(gs[1])
    ax_idx.set_xlim(t0, t1)
    ax_idx.set_ylim(0, 1)
    ax_idx.set_yticks([])
    ax_idx.set_xticks([])
    for spine in ax_idx.spines.values(): spine.set_visible(False)
    test_bits = 0x0F0F0F0F
    for i in range(16):
        t_cycle = 155_000 + i * 10_000   # in ps
        b0 = (test_bits >> (2*i)) & 1
        b1 = (test_bits >> (2*i + 1)) & 1
        pair = (b1 << 1) | b0
        color = "#1f77b4" if pair == 3 else "#ff7f0e" if pair == 0 else "gray"
        ax_idx.text(t_cycle + 5_000, 0.5, f"i={i}\n{b1}{b0}={pair}",
                    ha="center", va="center", fontsize=7, color=color, weight="bold")

    panel_specs = [
        # (signal_name, label, color, kind)
        ("clk",     "clk\n(100MHz)",  "blue",     "logic"),
        ("bits_in", "bits_in\n(QPSK pair)",  "purple",   "qpsk_pair"),
        ("tx_I",    "tx_I\n(I-axis ±A)", "red",      "iq"),
        ("tx_Q",    "tx_Q\n(Q-axis ±A)", "darkorange","iq"),
        ("llr0",    "llr0\n(I sign LLR)",   "darkcyan", "llr"),
        ("decoded", "decoded[31:0]\n(running output)", "black", "hex32"),
    ]

    for idx, (name, label, color, kind) in enumerate(panel_specs):
        ax = fig.add_subplot(gs[idx + 1])
        xs, ys = step_xy(ev.get(name, []), t0, t1)
        ax.step(xs, ys, where="post", color=color, linewidth=1.6)
        ax.set_xlim(t0, t1)
        ax.set_ylabel(label, fontsize=9.5, rotation=0, ha="right", va="center", labelpad=68)
        ax.grid(True, axis="x", linestyle=":", alpha=0.4)
        ax.tick_params(axis="y", labelsize=8)
        ax.tick_params(axis="x", labelsize=8)

        # Highlight reset region
        ax.axvspan(0, 95_000, color="#FFE0E0", alpha=0.25)

        if kind == "logic":
            ax.set_yticks([0, 1])
            ax.set_ylim(-0.3, 1.4)
        elif kind == "qpsk_pair":
            ax.set_yticks([0, 1, 2, 3])
            ax.set_ylim(-0.3, 3.4)
            for i in range(16):
                t_cycle = 155_000 + i * 10_000
                v = value_at(ev["bits_in"], t_cycle)
                if i % 2 == 0:
                    ax.text(t_cycle + 5_000, 3.0, str(v), ha="center", fontsize=7, color=color)
        elif kind == "iq":
            ax.set_yticks([-5793, 0, 5793])
            ax.set_yticklabels(["-A", "0", "+A"])
            ax.set_ylim(-7500, 7500)
            ax.axhline(0, color="gray", linewidth=0.4, linestyle=":")
        elif kind == "llr":
            ax.set_yticks([-50, 0, 50])
            ax.set_yticklabels(["-46", "0", "+45"])
            ax.set_ylim(-80, 80)
            ax.axhline(0, color="gray", linewidth=0.4, linestyle=":")
        elif kind == "hex32":
            ax.set_yticks([])
            ax.set_ylim(0, 1.2)
            seen_vals = set()
            for t, v in ev[name]:
                if t > t1: break
                if v in seen_vals: continue
                seen_vals.add(v)
                if t < 100_000 and v == 0: continue
                # color-code: full pass = green, intermediate = light gray
                fc = "#A5D6A7" if v == 0x0F0F0F0F else "#E8E8E8"
                ax.text(t + 1_000, 0.5, f"0x{v:08X}",
                        fontsize=8, ha="left", va="center",
                        family="monospace",
                        bbox=dict(boxstyle="round,pad=0.2", fc=fc, ec="gray", lw=0.5))

        if idx + 1 < len(panel_specs):
            ax.set_xticklabels([])

    # Final x label
    ax.set_xlabel("simulation time (ps)", fontsize=10)

    # Title
    fig.suptitle("Path X xsim — TEST_BITS_LO = 0x0F0F0F0F transmitted via QPSK, "
                 "looped back, demodulated, recovered bit-by-bit\n"
                 "Final: decoded[31:0] = 0x0F0F0F0F  ✓  errors = 0/32",
                 fontsize=13, y=0.965)

    # Legend / explanation box
    ann = (
        "Reading the trace (cycle = 10 ns):\n"
        "• bits_in  = {bit[2i+1], bit[2i]} from TEST_BITS_LO, drives qpsk_mod each clock\n"
        "• 0x0F0F0F0F → pair sequence 3,3,0,0 ×4 → tx_I/tx_Q toggle ±A every 2 clocks\n"
        "• qpsk_demod: +A → llr=+45 (bit=0)   -A → llr=-46 (bit=1)\n"
        "• decoded[bit_idx +: 2] captures llr signs each clock; bit_idx grows 0→2→4…→32\n"
        "• Verifier compares decoded vs TEST_BITS_LO: errors = 0/32 ⇒ identical RF result"
    )
    fig.text(0.07, 0.02, ann, fontsize=9, family="monospace",
             bbox=dict(boxstyle="round,pad=0.4", fc="#F8F8F8", ec="black"))

    out = "/home/ysara/fpga_hdl/simulation/path_x_waveform_annotated.png"
    plt.savefig(out, dpi=130, bbox_inches="tight")
    print(f"Saved: {out}")


if __name__ == "__main__":
    main()
