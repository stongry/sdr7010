#!/usr/bin/env python3
"""Hand-laid hierarchical block diagram for ofdm_ldpc_top.

Replaces netlistsvg's spaghetti auto-routed output with a clean
left-to-right TX/RX dataflow that matches the actual instantiations
in /home/ysara/fpga_hdl/ofdm_ldpc_top.v (verified via grep).
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

fig, ax = plt.subplots(figsize=(24, 13))
ax.set_xlim(0, 24)
ax.set_ylim(0, 13)
ax.axis("off")

TX_COLOR = "#D6E8FF"
RX_COLOR = "#FFE4D6"
CTRL_COLOR = "#E8E8E8"
DBG_COLOR = "#FFF6CC"
PORT_COLOR = "#F0F0F0"
TX_BORDER = "#1f4e8c"
RX_BORDER = "#a04020"
WIRE_TX = "#1f4e8c"
WIRE_RX = "#a04020"


def block(x, y, w, h, name, sub="", color=TX_COLOR, border=TX_BORDER):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.05",
        linewidth=1.6, edgecolor=border, facecolor=color))
    ax.text(x + w / 2, y + h / 2 + (0.18 if sub else 0),
            name, ha="center", va="center",
            fontsize=10, weight="bold")
    if sub:
        ax.text(x + w / 2, y + h / 2 - 0.22, sub,
                ha="center", va="center", fontsize=8, color="#404040",
                style="italic")


def port(x, y, label, side="left"):
    w, h = 1.5, 0.45
    ax.add_patch(patches.Polygon(
        [(x, y), (x + w - 0.2, y), (x + w, y + h / 2),
         (x + w - 0.2, y + h), (x, y + h)] if side == "left" else
        [(x + 0.2, y), (x + w, y), (x + w, y + h),
         (x + 0.2, y + h), (x, y + h / 2)],
        closed=True, linewidth=1.0,
        edgecolor="black", facecolor=PORT_COLOR))
    ax.text(x + w / 2, y + h / 2, label, ha="center",
            va="center", fontsize=8)


def wire(x1, y1, x2, y2, label="", color="black", lw=1.4,
         text_y_offset=0.18, text_color=None):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color=color,
                                lw=lw, shrinkA=0, shrinkB=0))
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + text_y_offset, label,
                ha="center", va="bottom", fontsize=8,
                color=text_color or color,
                bbox=dict(boxstyle="round,pad=0.15",
                          fc="white", ec="none", alpha=0.9))


# ===================== Title =========================
ax.text(12, 12.55,
        "ofdm_ldpc_top — hierarchical block diagram",
        ha="center", fontsize=15, weight="bold")
ax.text(12, 12.15,
        "TX path (top, blue)  ·  RX path (bottom, orange)  "
        "·  signals match ofdm_ldpc_top.v",
        ha="center", fontsize=10, color="#404040", style="italic")

# ===================== Left input ports =================
port(0.0, 10.50, "tx_info_bits[511:0]")
port(0.0,  9.85, "tx_valid_in")
port(0.0,  3.40, "rx_iq_i[15:0]")
port(0.0,  2.85, "rx_iq_q[15:0]")
port(0.0,  2.30, "rx_valid_in")
port(0.0,  1.75, "rx_frame_start")

# clk/rst_n in middle-left
port(0.0,  6.80, "clk")
port(0.0,  6.25, "rst_n")
ax.text(0.75, 7.45, "clk / rst_n fan out\nto every block",
        ha="center", fontsize=8, color="#404040", style="italic")

# ===================== TX chain (top row) =========================
ty = 10.0
block(2.4,  ty, 2.6, 1.4, "ldpc_encoder",
      "(1024,512) IRA QC\nZ=64, base 8×16",
      color=TX_COLOR, border=TX_BORDER)
block(6.0,  ty, 2.6, 1.4, "tx_subcarrier_map",
      "QPSK ⇒ 64 bins\nA=5793, NULL/PILOT",
      color=TX_COLOR, border=TX_BORDER)
block(9.6,  ty, 2.6, 1.4, "xfft_stub  u_ifft",
      "AXI-Stream IFFT-64\n(stub passthrough)",
      color=TX_COLOR, border=TX_BORDER)
block(13.2, ty, 2.6, 1.4, "cp_insert",
      "+16-sample CP\ndrives DAC",
      color=TX_COLOR, border=TX_BORDER)

# Right output ports for TX
port(22.5, 11.05, "tx_iq_i[15:0]",  side="right")
port(22.5, 10.50, "tx_iq_q[15:0]",  side="right")
port(22.5,  9.95, "tx_valid_out",   side="right")

# TX wires
wire(1.5, 10.7, 2.4, 10.7,  "tx_info_bits", color=WIRE_TX)
wire(1.5, 10.05, 2.4, 10.05, "tx_valid_in", color=WIRE_TX)
wire(5.0, 10.7, 6.0, 10.7,
     "enc_codeword[1023:0]\nenc_valid_out", color=WIRE_TX)
wire(8.6, 10.7, 9.6, 10.7,
     "ifft_s_tdata\nifft_s_tvalid/tready", color=WIRE_TX)
wire(12.2, 10.7, 13.2, 10.7,
     "ifft_m_tdata\nifft_m_tvalid/tready", color=WIRE_TX)
wire(15.8, 10.7, 22.5, 10.7,
     "cp_ins_tdata = {Q,I}\ncp_ins_tvalid", color=WIRE_TX)

# ===================== RX chain (bottom row) =========================
ry = 1.6
block(2.4,  ry, 2.4, 1.4, "cp_remove",
      "drop 16 CP\nframe_start sync",
      color=RX_COLOR, border=RX_BORDER)
block(5.4,  ry, 2.4, 1.4, "xfft_stub  u_fft",
      "AXI-Stream FFT-64\n(stub passthrough)",
      color=RX_COLOR, border=RX_BORDER)
block(8.4,  ry, 2.4, 1.4, "channel_est",
      "pilot-based\n1-tap eq",
      color=RX_COLOR, border=RX_BORDER)
block(11.4, ry, 2.4, 1.4, "rx_subcarrier_demap",
      "extract 48 data\nbins from 64",
      color=RX_COLOR, border=RX_BORDER)
block(14.4, ry, 2.0, 1.4, "qpsk_demod",
      "soft LLR 8-bit\nllr0 / llr1",
      color=RX_COLOR, border=RX_BORDER)
block(17.0, ry, 2.0, 1.4, "llr_buffer",
      "1024 × 8-bit\nbyte-addressable",
      color=RX_COLOR, border=RX_BORDER)
block(19.6, ry, 2.0, 1.4, "ldpc_decoder",
      "BP / hard-dec\n iter_count out",
      color=RX_COLOR, border=RX_BORDER)

# RX wires (left → right)
wire(1.5, 3.4, 2.4, 2.85, "rx_iq_i", color=WIRE_RX, text_y_offset=0.05)
wire(1.5, 2.85, 2.4, 2.6, "rx_iq_q", color=WIRE_RX, text_y_offset=-0.25)
wire(1.5, 2.30, 2.4, 2.30, "rx_valid_in", color=WIRE_RX)
wire(1.5, 1.75, 2.4, 1.85, "frame_start", color=WIRE_RX,
     text_y_offset=-0.30)

wire(4.8,  2.30, 5.4,  2.30, "cp_rem_tdata\ncp_rem_tvalid",
     color=WIRE_RX)
wire(7.8,  2.30, 8.4,  2.30, "fft_m_tdata\nfft_m_tvalid",
     color=WIRE_RX)
wire(10.8, 2.30, 11.4, 2.30, "eq_i/q_out\neq_valid_out",
     color=WIRE_RX)
wire(13.8, 2.30, 14.4, 2.30, "demap_i/q_out\ndemap_valid",
     color=WIRE_RX)
wire(16.4, 2.30, 17.0, 2.30, "llr0/llr1\ndemod_valid",
     color=WIRE_RX)
wire(19.0, 2.30, 19.6, 2.30, "llr_rd_data\nllr_rd_addr",
     color=WIRE_RX)

# Right output ports for RX
port(22.5, 1.40, "rx_decoded[511:0]", side="right")
port(22.5, 0.85, "rx_valid_out", side="right")
wire(21.6, 2.0, 22.5, 1.65, color=WIRE_RX, lw=1.0)

# ===================== clk/rst_n bus (visual hint) ===================
ax.add_patch(patches.Rectangle(
    (1.7, 6.05), 21.0, 0.05,
    linewidth=0, facecolor="#888888"))
ax.text(12.0, 5.80, "clk / rst_n  →  fan-out to all blocks above",
        ha="center", fontsize=8, color="#555555", style="italic")

# ===================== Debug pins (right side) =========================
# Sit in the empty band between TX outputs (y≥9.95) and the clk/rst bus
# (y=6.05). 8 ports stacked with 0.5 pitch, well clear of both rows.
dbg_x = 22.5
dbg_title_y = 9.40
dbgs = [
    (8.95, "dbg_enc_valid"),
    (8.45, "dbg_ifft_valid"),
    (7.95, "dbg_cp_rem_valid"),
    (7.45, "dbg_fft_m_valid"),
    (6.95, "dbg_eq_valid"),
    (4.95, "dbg_demod_valid"),
    (4.45, "dbg_llr_done"),
    (3.95, "dbg_chllr_decoded[511:0]"),
]
ax.text(dbg_x + 0.75, dbg_title_y, "EMIO debug pins\n(latched in ofdm_ldpc_pl)",
        ha="center", fontsize=8, color="#806600",
        style="italic", weight="bold")
for y, lab in dbgs:
    port(dbg_x, y, lab, side="right")

# Decorative legend
legend_x = 1.0
legend_y = 0.05
ax.add_patch(patches.Rectangle((legend_x, legend_y),
                               0.5, 0.4, color=TX_COLOR,
                               ec=TX_BORDER, lw=1.2))
ax.text(legend_x + 0.6, legend_y + 0.20, "TX path",
        fontsize=9, va="center")
ax.add_patch(patches.Rectangle((legend_x + 2.5, legend_y),
                               0.5, 0.4, color=RX_COLOR,
                               ec=RX_BORDER, lw=1.2))
ax.text(legend_x + 3.1, legend_y + 0.20, "RX path",
        fontsize=9, va="center")
ax.text(legend_x + 5.5, legend_y + 0.20,
        "data hand-verified against ofdm_ldpc_top.v "
        "(105–215) — module/wire names match RTL",
        fontsize=8.5, color="#404040", style="italic")

out = "/home/ysara/fpga_hdl/simulation/rtl_ofdm_ldpc_top.png"
plt.savefig(out, dpi=140, bbox_inches="tight", facecolor="white")
print(f"Saved {out}")
