#!/usr/bin/env python3
"""Hand-routed hierarchical block diagram for ofdm_ldpc_top.

Replaces the netlistsvg auto-routed rtl_ofdm_ldpc_top.png whose router
piled debug pins on top of each other and crossed AXI-Stream signals at
the TX output. Every block name + port + width comes verbatim from
/home/ysara/fpga_hdl/ofdm_ldpc_top.v (instances u_ldpc_enc, u_tx_map,
u_ifft, u_cp_ins, u_cp_rem, u_fft, u_ch_est, u_rx_demap, u_qpsk_demod,
u_llr_buf, u_ldpc_dec).
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.path import Path

# ---------------------------------------------------------------------------
# Canvas (logical units; matplotlib inches matches 1:1 for predictable layout)
# ---------------------------------------------------------------------------
W, H = 28.0, 17.0
fig, ax = plt.subplots(figsize=(W, H))
ax.set_xlim(0, W); ax.set_ylim(0, H)
ax.axis("off")

TX_COLOR  = "#D9EAF7"
RX_COLOR  = "#FCE4D6"
DBG_COLOR = "#FFF2CC"
PORT_COLOR = "#FFFFFF"

TX_Y  = 13.2
RX_Y  = 6.6
DEC_Y = 2.7
BLK_H = 1.6
PORT_H = 1.7

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def block(x, y_centre, w, label, sub="", color=TX_COLOR, h=BLK_H):
    yb = y_centre - h / 2
    ax.add_patch(patches.FancyBboxPatch(
        (x, yb), w, h, boxstyle="round,pad=0.04",
        linewidth=1.4, edgecolor="black", facecolor=color))
    ax.text(x + w / 2, yb + h * 0.62, label,
            ha="center", va="center", fontsize=12, weight="bold")
    if sub:
        ax.text(x + w / 2, yb + h * 0.22, sub,
                ha="center", va="center", fontsize=9, style="italic", color="#222")
    return (x, yb, x + w, yb + h)


def port(x, y_centre, w, label, color=PORT_COLOR, h=PORT_H):
    return block(x, y_centre, w, label, "", color=color, h=h)


def harrow(x1, x2, y, label_top="", label_bot="", color="black"):
    ax.annotate("", xy=(x2, y), xytext=(x1, y),
                arrowprops=dict(arrowstyle="-|>", color=color,
                                lw=1.7, mutation_scale=15))
    if label_top:
        ax.text((x1 + x2) / 2, y + 0.22, label_top,
                ha="center", va="bottom", fontsize=9, color=color,
                bbox=dict(boxstyle="round,pad=0.12", fc="white", ec="none", alpha=0.92))
    if label_bot:
        ax.text((x1 + x2) / 2, y - 0.22, label_bot,
                ha="center", va="top", fontsize=8.5, color="#444", style="italic")


def varrow(x, y1, y2, label_right="", color="black"):
    ax.annotate("", xy=(x, y2), xytext=(x, y1),
                arrowprops=dict(arrowstyle="-|>", color=color,
                                lw=1.7, mutation_scale=15))
    if label_right:
        ax.text(x + 0.18, (y1 + y2) / 2, label_right,
                ha="left", va="center", fontsize=9, color=color, style="italic")


# ---------------------------------------------------------------------------
# Title
# ---------------------------------------------------------------------------
ax.text(W / 2, H - 0.45,
        "ofdm_ldpc_top  —  hierarchical RTL block diagram",
        ha="center", fontsize=20, weight="bold")
ax.text(W / 2, H - 1.05,
        "TX path (top, blue)   —   RX path (bottom, orange)   —   "
        "DEBUG taps (right, yellow)   —   "
        "all instance names match ofdm_ldpc_top.v   —   "
        "clk / rst_n fan-out to every submodule (not drawn per-pin)",
        ha="center", fontsize=11, style="italic", color="#444")

# ---------------------------------------------------------------------------
# TX DATAPATH
# ---------------------------------------------------------------------------
ax.text(W / 2, TX_Y + 1.7,
        "TX  DATAPATH    (encode → map → IFFT → CP-insert → DAC)",
        ha="center", fontsize=13, weight="bold", color="#114488")

# left input port
p_txi  = port (0.3,  TX_Y, 2.4, "tx_info_bits[511:0]\ntx_valid_in")

# chain
b_enc  = block(3.0,  TX_Y, 2.5, "u_ldpc_enc",
               "ldpc_encoder\n(1024,512) IRA QC", TX_COLOR)
b_map  = block(6.0,  TX_Y, 2.5, "u_tx_map",
               "tx_subcarrier_map\n48d + 4p + 12N", TX_COLOR)
b_ifft = block(9.0,  TX_Y, 2.0, "u_ifft",
               "xfft_stub  (IFFT)\n64-pt complex", TX_COLOR)
b_cp   = block(11.5, TX_Y, 2.4, "u_cp_ins",
               "cp_insert\nCP=16, ping-pong", TX_COLOR)

# right output port
p_txo  = port (14.4, TX_Y, 2.6,
              "tx_iq_i [15:0]\ntx_iq_q [15:0]\ntx_valid_out")

# horizontal wires + AXI-S annotations (label_top above arrow, label_bot below)
harrow(2.7,  3.0,  TX_Y, "valid_in",       "1 pulse / block")
harrow(5.5,  6.0,  TX_Y, "enc_codeword",   "1024-bit cw")
harrow(8.5,  9.0,  TX_Y, "ifft_s_tdata",   "(I,Q) freq")
harrow(11.0, 11.5, TX_Y, "ifft_m_tdata",   "(I,Q) time")
harrow(13.9, 14.4, TX_Y, "cp_ins_tdata",   "+CP, 80/sym")

# ---------------------------------------------------------------------------
# Loopback bridge (between TX-out and RX-in, far right)
# ---------------------------------------------------------------------------
LB_X1, LB_X2 = 17.8, 21.0
LB_Y_C = (TX_Y + RX_Y) / 2  # ≈ 9.9
LB_H = 1.6
ax.add_patch(patches.FancyBboxPatch(
    (LB_X1, LB_Y_C - LB_H / 2), LB_X2 - LB_X1, LB_H,
    boxstyle="round,pad=0.06", linewidth=1.5,
    edgecolor="#226622", facecolor="#E6FFEA"))
ax.text((LB_X1 + LB_X2) / 2, LB_Y_C + 0.3,
        "DIGITAL  LOOP-BACK", ha="center", va="center",
        fontsize=12, weight="bold", color="#264")
ax.text((LB_X1 + LB_X2) / 2, LB_Y_C - 0.3,
        "wire (Path X simulation)   /   AD9363 + SMA (Path A board)",
        ha="center", va="center", fontsize=9, style="italic", color="#264")

# elbow from p_txo right edge → top-left of loopback
elbow_x = (p_txo[2] + LB_X1) / 2
ax.annotate("", xy=(LB_X1, LB_Y_C + LB_H / 2 - 0.0),
            xytext=(p_txo[2], TX_Y),
            arrowprops=dict(arrowstyle="-|>", color="black", lw=1.7,
                            mutation_scale=15,
                            connectionstyle="angle,angleA=0,angleB=90,rad=12"))
ax.text(elbow_x + 0.2, TX_Y + 0.25, "tx_iq",
        ha="left", va="bottom", fontsize=9, style="italic")

# ---------------------------------------------------------------------------
# RX DATAPATH  (right → left)
# ---------------------------------------------------------------------------
ax.text(W / 2, RX_Y + 1.7,
        "RX  DATAPATH    (CP-remove → FFT → channel-est → demap → demod → LLR → LDPC decode)",
        ha="center", fontsize=13, weight="bold", color="#A04400")

# RX input port (right side — fed by loopback)
p_rxi  = port (19.0, RX_Y, 2.6,
               "rx_iq_i [15:0]\nrx_iq_q [15:0]\nrx_valid_in / rx_frame_start")

# chain (RTL — right → left)
b_cprm = block(15.6, RX_Y, 2.6, "u_cp_rem",
               "cp_remove\nframe_start sync, drop 16/80", RX_COLOR)
b_fft  = block(12.7, RX_Y, 2.2, "u_fft",
               "xfft_stub  (FFT)\n64-pt", RX_COLOR)
b_ch   = block(9.7,  RX_Y, 2.5, "u_ch_est",
               "channel_est\nSTREAM_MODE pilot eq", RX_COLOR)
b_dmap = block(6.6,  RX_Y, 2.6, "u_rx_demap",
               "rx_subcarrier_demap\ndrop NULL/pilot → 48 data", RX_COLOR)
b_dmod = block(3.5,  RX_Y, 2.6, "u_qpsk_demod",
               "qpsk_demod\nSCALE=7 LLR + sat8", RX_COLOR)
b_llr  = block(0.4,  RX_Y, 2.6, "u_llr_buf",
               "llr_buffer\n1024 LLRs (DRAM)", RX_COLOR)

# elbow from loopback bottom → top of p_rxi
ax.annotate("", xy=(p_rxi[0] + (p_rxi[2] - p_rxi[0]) / 2, RX_Y + PORT_H / 2),
            xytext=((LB_X1 + LB_X2) / 2, LB_Y_C - LB_H / 2),
            arrowprops=dict(arrowstyle="-|>", color="black", lw=1.7,
                            mutation_scale=15,
                            connectionstyle="angle,angleA=-90,angleB=0,rad=10"))
ax.text((LB_X1 + LB_X2) / 2 + 0.2, (RX_Y + LB_Y_C) / 2,
        "rx_iq", ha="left", va="center", fontsize=9, style="italic")

# RX horizontal wires (rightward source → leftward sink, arrow points LEFT)
harrow(19.0, 18.2, RX_Y, "rx_iq",        "raw I/Q",       color="#A04400")
harrow(15.6, 15.3, RX_Y, "cp_rem_tdata", "AXI-S, 64/sym", color="#A04400")
harrow(12.7, 12.2, RX_Y, "fft_m_tdata",  "freq bins",     color="#A04400")
harrow(9.7,  9.2,  RX_Y, "eq_tdata",     "equalised I/Q", color="#A04400")
harrow(6.6,  6.1,  RX_Y, "demap_tdata",  "48 data/sym",   color="#A04400")
harrow(3.5,  3.0,  RX_Y, "demod_llr",    "8-bit signed",  color="#A04400")

# ---------------------------------------------------------------------------
# u_ldpc_dec (drops below u_llr_buf) + rx_decoded output port
# ---------------------------------------------------------------------------
b_dec  = block(0.4, DEC_Y, 2.6, "u_ldpc_dec",
               "ldpc_decoder\nmin-sum BP, MAX_ITER=10", RX_COLOR)
varrow(b_llr[0] + (b_llr[2] - b_llr[0]) / 2,
       RX_Y - BLK_H / 2,
       DEC_Y + BLK_H / 2,
       "1024 LLRs", color="#A04400")

p_rxo  = port (3.4, DEC_Y, 2.8,
               "rx_decoded[511:0]\nrx_valid_out", h=1.4)
harrow(b_dec[2], p_rxo[0], DEC_Y, "decoded bits", color="#A04400")

# ---------------------------------------------------------------------------
# DEBUG TAPS column  (right edge)
# ---------------------------------------------------------------------------
DBG_X = 24.6
DBG_W = 3.2

ax.add_patch(patches.FancyBboxPatch(
    (DBG_X - 0.1, 0.4), DBG_W + 0.2, H - 1.7,
    boxstyle="round,pad=0.05", linewidth=1.0,
    edgecolor="#9C7A00", facecolor="#FFFCEC"))
ax.text(DBG_X + DBG_W / 2, H - 1.55,
        "DEBUG  TAPS\n(latched in ofdm_ldpc_pl, EMIO out)",
        ha="center", va="center", fontsize=11.5, weight="bold", color="#7A5C00")

dbg_pins = [
    ("dbg_enc_valid",        b_enc),
    ("dbg_ifft_valid",       b_map),
    ("dbg_cp_rem_valid",     b_cprm),
    ("dbg_fft_m_valid",      b_fft),
    ("dbg_eq_valid",         b_ch),
    ("dbg_demod_valid",      b_dmod),
    ("dbg_llr_done",         b_llr),
    ("dbg_chllr_decoded[511:0]", b_dec),
]

n = len(dbg_pins)
y_top, y_bot = H - 2.6, 1.0
y_step = (y_top - y_bot) / (n - 1)
for i, (name, src_blk) in enumerate(dbg_pins):
    pin_y = y_top - i * y_step
    # pin pill
    ax.add_patch(patches.FancyBboxPatch(
        (DBG_X + 0.15, pin_y - 0.30), DBG_W - 0.3, 0.60,
        boxstyle="round,pad=0.03", linewidth=1.0,
        edgecolor="#7A5C00", facecolor=DBG_COLOR))
    ax.text(DBG_X + DBG_W / 2, pin_y, name,
            ha="center", va="center", fontsize=9.5, family="monospace")
    # leader: from top edge of source block (TX) or bottom edge (RX) → corridor → pin
    sx = src_blk[2]                       # right edge of block
    is_tx = (src_blk[1] + src_blk[3]) / 2 > 9.0
    sy = src_blk[3] if is_tx else src_blk[1]  # top for TX, bottom for RX
    # use a per-pin corridor x so the verticals don't all overlap
    corridor_x = 21.6 + 0.30 * i
    pts = [(sx, sy),
           (sx, sy + 0.4 if is_tx else sy - 0.4),
           (corridor_x, sy + 0.4 if is_tx else sy - 0.4),
           (corridor_x, pin_y),
           (DBG_X + 0.15, pin_y)]
    codes = [Path.MOVETO] + [Path.LINETO] * 4
    ax.add_patch(patches.PathPatch(Path(pts, codes),
                                   fill=False, edgecolor="#B89500",
                                   linewidth=1.0, linestyle=(0, (4, 2))))
    ax.annotate("", xy=(DBG_X + 0.15, pin_y),
                xytext=(DBG_X + 0.0, pin_y),
                arrowprops=dict(arrowstyle="-|>", color="#B89500",
                                lw=1.0, mutation_scale=12))

# ---------------------------------------------------------------------------
# Legend + latency note (bottom-left)
# ---------------------------------------------------------------------------
def lg_box(x, y, color, label, edgecolor="black"):
    ax.add_patch(patches.Rectangle((x, y), 0.55, 0.35,
                                   facecolor=color, edgecolor=edgecolor))
    ax.text(x + 0.7, y + 0.18, label, va="center", fontsize=10)

lg_y = 0.55
ax.add_patch(patches.Rectangle((0.3, lg_y - 0.15), 11.6, 0.85,
                               facecolor="white", edgecolor="#999",
                               linewidth=0.8))
lg_box(0.5, lg_y, TX_COLOR, "TX submodule")
lg_box(3.4, lg_y, RX_COLOR, "RX submodule")
lg_box(6.4, lg_y, DBG_COLOR, "debug pin", edgecolor="#7A5C00")
lg_box(8.6, lg_y, PORT_COLOR, "top-level port")

ax.text(W / 2, 0.25,
        "Pipeline latencies — ldpc_enc 18 cy   |   IFFT 64 cy   |   "
        "+CP 16 sample   |   channel_est 1 cy   |   qpsk_demod 1 cy   |   "
        "ldpc_decode ≈ 8200 cy   ·   fclk = 50 MHz",
        ha="center", fontsize=10, color="#444", style="italic")

out = "/home/ysara/fpga_hdl/simulation/rtl_ofdm_ldpc_top.png"
plt.savefig(out, dpi=130, bbox_inches="tight")
print(f"Saved {out}")
plt.close(fig)
