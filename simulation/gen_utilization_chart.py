#!/usr/bin/env python3
"""Render Vivado utilization data as bar+pie charts."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# Real data from /tmp/util_digital.rpt (digital ofdm_ldpc, build #34)
# and /tmp/util_pluto_ldsdr.rpt (Path A pluto_ldsdr)
designs = {
    "Digital OFDM+LDPC\n(ldsdr_digital_bd)\nbuild #34 PASS": {
        "LUT (Logic)":        (5379, 17600),
        "LUT (Memory)":       (3649, 6000),
        "Slice Registers":    (5519, 35200),
        "F7/F8 Muxes":        (1067, 13200),
        "Block RAM (RAMB36)": (0,    60),
        "DSP48E1":            (0,    80),
    },
    "Path A pluto_ldsdr\n(ADI HDL pluto port,\nclg400 + LVDS_25)": {
        "LUT (Logic)":        (11041, 17600),
        "LUT (Memory)":       (1086, 6000),
        "Slice Registers":    (21631, 35200),
        "F7/F8 Muxes":        (84,    13200),
        "Block RAM (RAMB36)": (2,     60),
        "DSP48E1":            (72,    80),
    }
}

# Bigger figure + explicit gridspec spacing so titles never collide.
fig = plt.figure(figsize=(20, 14))
gs = fig.add_gridspec(2, 2, hspace=0.85, wspace=0.55,
                      left=0.07, right=0.97, top=0.90, bottom=0.05)
axes = [fig.add_subplot(gs[i, j]) for i in range(2) for j in range(2)]


def draw_barh(ax, res, title):
    labels = list(res.keys())
    used = [v[0] for v in res.values()]
    total = [v[1] for v in res.values()]
    util_pct = [u / t * 100 if t > 0 else 0 for u, t in zip(used, total)]
    y = np.arange(len(labels))
    bars = ax.barh(y, util_pct,
                   color=["#1f77b4", "#ff7f0e", "#2ca02c",
                          "#d62728", "#9467bd", "#8c564b"])
    # Place text ALWAYS outside the bar (right of the bar end) to avoid
    # the previous overlap where wide bars covered their own labels.
    for i, (u, t, p, bar) in enumerate(zip(used, total, util_pct, bars)):
        text_x = p + 2
        ax.text(text_x, i, f"{u:,} / {t:,}  ({p:.1f}%)",
                va="center", ha="left",
                fontsize=10, color="black",
                bbox=dict(boxstyle="round,pad=0.2",
                          fc="white", ec="none", alpha=0.85))
    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=10)
    # Extra headroom on the right so the (xx.x%) labels never get clipped.
    ax.set_xlim(0, 145)
    ax.set_xlabel("utilisation %", fontsize=11)
    ax.set_title(title, fontsize=12, pad=14)
    ax.grid(True, axis="x", linestyle=":", alpha=0.4)
    ax.invert_yaxis()


# Bar chart 1: digital
draw_barh(axes[0],
          designs["Digital OFDM+LDPC\n(ldsdr_digital_bd)\nbuild #34 PASS"],
          "Digital OFDM+LDPC (build #34, pass_flag=1)\n"
          "full bitstream resource usage on xc7z010clg400-2")

# Bar chart 2: pluto_ldsdr
draw_barh(axes[1],
          designs["Path A pluto_ldsdr\n(ADI HDL pluto port,\nclg400 + LVDS_25)"],
          "Path A pluto_ldsdr (clg400 + LVDS_25)\n"
          "ADI standard pluto BD with axi_ad9361 + axi_dmac×2")


def draw_pie(ax, sizes, labels, title):
    colors = ["#ff7f0e", "#d62728", "#1f77b4", "#dddddd"]
    total = sum(sizes)
    # Push tiny slices (<8%) outward so their labels don't pile up.
    explode = [0.18 if s / total < 0.08 else 0.0 for s in sizes]

    def fmt_pct(p):
        # Hide percentage text on tiny slices — the label itself carries the count.
        return f"{p:.1f}%" if p >= 3.0 else ""

    wedges, texts, autotexts = ax.pie(
        sizes, labels=labels, colors=colors,
        autopct=fmt_pct, startangle=140,
        pctdistance=0.72, labeldistance=1.22,
        explode=explode,
        wedgeprops={"edgecolor": "white", "linewidth": 1},
        textprops={"fontsize": 10},
    )
    for at in autotexts:
        at.set_fontsize(10)
        at.set_weight("bold")
        at.set_color("white")
    ax.set_title(title, fontsize=12, pad=22)


# Pie chart: digital LUT breakdown
draw_pie(axes[2],
         [3648, 1, 5378, 17600 - 5379 - 3649],
         ["LUT as Distributed RAM\n3,648",
          "LUT as Shift Reg\n1",
          "LUT as Combinational Logic\n5,378",
          "Free LUTs\n8,572"],
         "Digital design — LUT breakdown\n"
         "(total: 9,028 used / 17,600 available)")

# Pie chart: Path A LUT breakdown
draw_pie(axes[3],
         [120, 966, 11040, 17600 - 12127],
         ["LUT as DRAM\n120",
          "LUT as Shift Reg\n966",
          "LUT as Combinational Logic\n11,040",
          "Free LUTs\n5,473"],
         "Path A pluto_ldsdr — LUT breakdown\n"
         "(total: 12,127 used / 17,600 available)")

fig.suptitle("Vivado 2024.2 utilisation report  |  device: xc7z010clg400-2  |  speed: -2",
             fontsize=15, weight="bold", y=0.965)

out = "/home/ysara/fpga_hdl/simulation/utilization_chart.png"
plt.savefig(out, dpi=120, bbox_inches="tight")
print(f"Saved {out}")
plt.close(fig)

# ---------------------------------------------------------------------------
# RTX wiring diagram (unchanged layout, kept here so a single script regenerates
# both PNGs). No overlap issues reported on this one.
# ---------------------------------------------------------------------------
fig2, ax = plt.subplots(figsize=(15, 9))
ax.set_xlim(0, 16); ax.set_ylim(0, 10)
ax.axis("off")

import matplotlib.patches as patches

def box(x, y, w, h, label, color="#E0F0FF", border="black"):
    ax.add_patch(patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05",
                                         linewidth=1.5, edgecolor=border, facecolor=color))
    ax.text(x+w/2, y+h/2, label, ha="center", va="center", fontsize=9, weight="bold")

def arrow(x1, y1, x2, y2, label="", color="black"):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color=color, lw=1.5))
    if label:
        ax.text((x1+x2)/2, (y1+y2)/2 + 0.15, label, ha="center", fontsize=8, color=color, style="italic")

box(0.5, 6.0, 3.5, 1.8, "Linux Host PC\n(Manjaro)\npython3 path_x_v3.py\nlibiio", color="#FFF5DA")
box(5.5, 6.0, 3.5, 1.8, "LDSDR 7010 rev2.1\nXC7Z010CLG400-2 + AD9363\n+ Linux iio + axi_dmac\n+ axi_ad9361", color="#E0F0FF")
box(11.5, 5.0, 3.0, 3.0, "RF Loop\nTX1 ── SMA ── RX1\n(no attenuator)\nTX_ATTEN = -75 dB\nLO = 2.4 GHz", color="#FFE0E0")
box(0.5, 2.5, 3.5, 1.8, "FT4232H USB\nUART JTAG\n/dev/ttyUSB0..3", color="#E0FFE0")
box(5.5, 2.5, 3.5, 1.8, "Build Server\neea@10.24.79.1:2424\nVivado 2024.2", color="#F0E0FF")
box(0.5, 0.3, 14.0, 1.5,
    "Test workflow:\n"
    "  ① Build .bit on build server →  ② bootgen BOOT.bin →  ③ Write SD →  "
    "④ Boot Linux →  ⑤ python3 path_x_v3.py →  ⑥ 0/32 bit errors PASS",
    color="#FAFAD2")

arrow(4.0, 6.9, 5.5, 6.9, "USB CDC ethernet\n192.168.2.10 ↔ 192.168.2.1")
arrow(9.0, 6.9, 11.5, 6.5, "AD9363 LVDS DDR")
arrow(11.5, 5.0, 11.5, 4.5, "")
ax.annotate("RF cable\nself-loopback", xy=(13.0, 4.5), fontsize=8, ha="center", color="darkred")
arrow(11.5, 4.5, 11.5, 5.0, "")
arrow(4.0, 3.4, 5.5, 3.4, "USB JTAG / UART")
arrow(4.0, 6.0, 4.0, 4.3, "")
ax.annotate("(monitoring)", xy=(4.2, 5.1), fontsize=8, color="gray", style="italic")
arrow(7.5, 6.0, 7.5, 4.3, "")
ax.annotate("(SCP)", xy=(7.7, 5.1), fontsize=8, color="gray", style="italic")
arrow(7.5, 4.3, 7.5, 6.0, "")

ax.text(13.0, 8.5, "RF chain:\nTX_LO 2.4GHz ↑\n    ↓ baseband\nfs=2.5 MHz\n12-bit DAC\n→ SMA short ←\n12-bit ADC\nrxgain=30 dB",
        fontsize=8, ha="center", va="top",
        bbox=dict(boxstyle="round,pad=0.3", fc="#FFF8DC", ec="brown"))

ax.set_title("LDSDR 7010 rev2.1 — Test Bench Wiring (RTX Diagram)",
             fontsize=14, weight="bold", pad=15)

out2 = "/home/ysara/fpga_hdl/simulation/rtx_wiring.png"
plt.savefig(out2, dpi=120, bbox_inches="tight")
print(f"Saved {out2}")
