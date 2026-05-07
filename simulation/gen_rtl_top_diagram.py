#!/usr/bin/env python3
"""Hand-routed hierarchical block diagram for ofdm_ldpc_top.

Replaces the netlistsvg auto-routed PNG (which produced overlapping
debug pins) AND the prior corridor version (which produced too many
crossing dashed leader lines).

This version places each debug tap LABEL DIRECTLY on the source block —
no long leader lines — keeping the data-flow geometry totally clean.
All instance names + ports + widths are taken verbatim from
/home/ysara/fpga_hdl/ofdm_ldpc_top.v.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------
W, H = 26.0, 15.0
fig, ax = plt.subplots(figsize=(W, H))
ax.set_xlim(0, W); ax.set_ylim(0, H)
ax.axis("off")

TX_COLOR  = "#D9EAF7"
RX_COLOR  = "#FCE4D6"
DBG_COLOR = "#FFF2CC"
PORT_COLOR = "#FFFFFF"

TX_Y  = 11.4
RX_Y  = 6.2
DEC_Y = 2.8
BLK_H = 1.7
PORT_H = 1.85


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def block(x, y_centre, w, label, sub="", color=TX_COLOR, h=BLK_H,
          dbg_label=None, dbg_side="top"):
    """Draw a block. If dbg_label is supplied, attach a small yellow
    pill to the top (TX) or bottom (RX) of the block."""
    yb = y_centre - h / 2
    ax.add_patch(patches.FancyBboxPatch(
        (x, yb), w, h, boxstyle="round,pad=0.04",
        linewidth=1.4, edgecolor="black", facecolor=color))
    ax.text(x + w / 2, yb + h * 0.65, label,
            ha="center", va="center", fontsize=12.5, weight="bold")
    if sub:
        ax.text(x + w / 2, yb + h * 0.25, sub,
                ha="center", va="center",
                fontsize=9.5, style="italic", color="#222")
    if dbg_label is not None:
        if dbg_side == "top":
            py = yb + h + 0.20
            ax.add_patch(patches.FancyBboxPatch(
                (x + 0.05, py), w - 0.1, 0.42,
                boxstyle="round,pad=0.02", linewidth=0.9,
                edgecolor="#7A5C00", facecolor=DBG_COLOR))
            ax.text(x + w / 2, py + 0.21, dbg_label,
                    ha="center", va="center",
                    fontsize=9, family="monospace", color="#5A4400")
        else:
            py = yb - 0.62
            ax.add_patch(patches.FancyBboxPatch(
                (x + 0.05, py), w - 0.1, 0.42,
                boxstyle="round,pad=0.02", linewidth=0.9,
                edgecolor="#7A5C00", facecolor=DBG_COLOR))
            ax.text(x + w / 2, py + 0.21, dbg_label,
                    ha="center", va="center",
                    fontsize=9, family="monospace", color="#5A4400")
    return (x, yb, x + w, yb + h)


def port_box(x, y_centre, w, label, color=PORT_COLOR, h=PORT_H):
    yb = y_centre - h / 2
    ax.add_patch(patches.FancyBboxPatch(
        (x, yb), w, h, boxstyle="round,pad=0.04",
        linewidth=1.4, edgecolor="black", facecolor=color))
    ax.text(x + w / 2, y_centre, label,
            ha="center", va="center", fontsize=10.5, family="monospace")
    return (x, yb, x + w, yb + h)


def harrow(x1, x2, y, sig="", note="", color="black"):
    ax.annotate("", xy=(x2, y), xytext=(x1, y),
                arrowprops=dict(arrowstyle="-|>", color=color,
                                lw=1.8, mutation_scale=16))
    if sig:
        ax.text((x1 + x2) / 2, y + 0.22, sig,
                ha="center", va="bottom", fontsize=9, color=color,
                bbox=dict(boxstyle="round,pad=0.12",
                          fc="white", ec="none", alpha=0.92))
    if note:
        ax.text((x1 + x2) / 2, y - 0.22, note,
                ha="center", va="top", fontsize=8.5,
                color="#444", style="italic")


def varrow(x, y1, y2, sig="", color="black"):
    ax.annotate("", xy=(x, y2), xytext=(x, y1),
                arrowprops=dict(arrowstyle="-|>", color=color,
                                lw=1.8, mutation_scale=16))
    if sig:
        ax.text(x + 0.18, (y1 + y2) / 2, sig,
                ha="left", va="center", fontsize=9, color=color, style="italic")


# ---------------------------------------------------------------------------
# Title
# ---------------------------------------------------------------------------
ax.text(W / 2, H - 0.35,
        "ofdm_ldpc_top  —  hierarchical RTL block diagram",
        ha="center", fontsize=20, weight="bold")
ax.text(W / 2, H - 0.95,
        "blue = TX submodules,   orange = RX submodules,   "
        "yellow pill above/below = EMIO debug tap (matches ofdm_ldpc_top.v)   "
        "—   clk / rst_n fan-out to all blocks (not drawn)",
        ha="center", fontsize=10.5, style="italic", color="#444")

# ---------------------------------------------------------------------------
# TX DATAPATH
# ---------------------------------------------------------------------------
ax.text(W / 2, TX_Y + 1.95,
        "TX  DATAPATH    encode → map → IFFT → CP-insert → DAC",
        ha="center", fontsize=13.5, weight="bold", color="#114488")

p_txi  = port_box(0.4,  TX_Y, 2.6,
                  "tx_info_bits[511:0]\ntx_valid_in")

b_enc  = block(3.4,  TX_Y, 2.6, "u_ldpc_enc",
               "ldpc_encoder\n(1024,512) IRA QC", TX_COLOR,
               dbg_label="dbg_enc_valid", dbg_side="top")
b_map  = block(6.6,  TX_Y, 2.6, "u_tx_map",
               "tx_subcarrier_map\n48d + 4p + 12N", TX_COLOR,
               dbg_label="dbg_ifft_valid", dbg_side="top")
b_ifft = block(9.8,  TX_Y, 2.2, "u_ifft",
               "xfft_stub  (IFFT)\n64-pt complex", TX_COLOR)
b_cp   = block(12.6, TX_Y, 2.6, "u_cp_ins",
               "cp_insert\nCP=16, ping-pong", TX_COLOR)

p_txo  = port_box(15.8, TX_Y, 2.8,
                  "tx_iq_i [15:0]\ntx_iq_q [15:0]\ntx_valid_out")

# TX wires (every label fits in the visible white-space gap)
harrow(p_txi[2],  b_enc[0],  TX_Y, "valid_in",      "1 pulse / block")
harrow(b_enc[2],  b_map[0],  TX_Y, "enc_codeword",  "1024 b")
harrow(b_map[2],  b_ifft[0], TX_Y, "ifft_s_tdata",  "(I,Q) freq")
harrow(b_ifft[2], b_cp[0],   TX_Y, "ifft_m_tdata",  "(I,Q) time")
harrow(b_cp[2],   p_txo[0],  TX_Y, "cp_ins_tdata",  "+CP, 80/sym")

# ---------------------------------------------------------------------------
# Loopback bridge between TX-out and RX-in (right side)
# ---------------------------------------------------------------------------
LB_X1, LB_X2 = 19.4, 23.6
LB_Y_C = (TX_Y + RX_Y) / 2
LB_H = 1.7
ax.add_patch(patches.FancyBboxPatch(
    (LB_X1, LB_Y_C - LB_H / 2), LB_X2 - LB_X1, LB_H,
    boxstyle="round,pad=0.06", linewidth=1.6,
    edgecolor="#226622", facecolor="#E6FFEA"))
ax.text((LB_X1 + LB_X2) / 2, LB_Y_C + 0.32,
        "DIGITAL  LOOP-BACK", ha="center", va="center",
        fontsize=12.5, weight="bold", color="#264")
ax.text((LB_X1 + LB_X2) / 2, LB_Y_C - 0.32,
        "wire (Path X simulation)   /   AD9363 + SMA (Path A board)",
        ha="center", va="center", fontsize=9, style="italic", color="#264")

# elbow connectors:  p_txo (TX out) → loopback (top-left)
LB_TOP_X = LB_X1 + 0.6
ax.plot([p_txo[2], LB_TOP_X, LB_TOP_X],
        [TX_Y, TX_Y, LB_Y_C + LB_H / 2],
        color="black", lw=1.8)
ax.annotate("", xy=(LB_TOP_X, LB_Y_C + LB_H / 2),
            xytext=(LB_TOP_X, LB_Y_C + LB_H / 2 + 0.4),
            arrowprops=dict(arrowstyle="-|>", color="black", lw=1.8,
                            mutation_scale=16))
ax.text(LB_TOP_X + 0.18, (TX_Y + LB_Y_C + LB_H / 2) / 2,
        "tx_iq", ha="left", va="center", fontsize=9, style="italic")

# loopback (bottom-right) → RX input port
LB_BOT_X = LB_X2 - 0.8
# The RX input port will sit just BELOW the loopback box (defined next).
# So we route loopback bottom edge → directly down into the RX port top.
RX_PORT_X1 = 19.4   # match LB_X1 so the loopback feeds straight down

# ---------------------------------------------------------------------------
# RX DATAPATH  (right → left)
# ---------------------------------------------------------------------------
ax.text(W / 2, RX_Y + 1.95,
        "RX  DATAPATH    CP-remove → FFT → channel-est → demap → demod → LLR → LDPC decode",
        ha="center", fontsize=13.5, weight="bold", color="#A04400")

p_rxi  = port_box(19.4, RX_Y, 4.2,
                  "rx_iq_i [15:0]\nrx_iq_q [15:0]\n"
                  "rx_valid_in / rx_frame_start", h=PORT_H)

# loopback bottom → rx_iq port top
ax.plot([LB_TOP_X, LB_TOP_X, p_rxi[0] + (p_rxi[2] - p_rxi[0]) / 2],
        [LB_Y_C - LB_H / 2, RX_Y + PORT_H / 2 + 0.0,
         RX_Y + PORT_H / 2 + 0.0],
        color="black", lw=1.8)
ax.annotate("", xy=(p_rxi[0] + (p_rxi[2] - p_rxi[0]) / 2,
                    RX_Y + PORT_H / 2),
            xytext=(p_rxi[0] + (p_rxi[2] - p_rxi[0]) / 2,
                    RX_Y + PORT_H / 2 + 0.4),
            arrowprops=dict(arrowstyle="-|>", color="black", lw=1.8,
                            mutation_scale=16))
ax.text(LB_TOP_X + 0.18, (LB_Y_C - LB_H / 2 + RX_Y + PORT_H / 2) / 2,
        "rx_iq", ha="left", va="center", fontsize=9, style="italic")

# RX chain — right-to-left
b_cprm = block(16.5, RX_Y, 2.6, "u_cp_rem",
               "cp_remove\nframe_start sync", RX_COLOR,
               dbg_label="dbg_cp_rem_valid", dbg_side="bot")
b_fft  = block(13.6, RX_Y, 2.4, "u_fft",
               "xfft_stub  (FFT)\n64-pt", RX_COLOR,
               dbg_label="dbg_fft_m_valid", dbg_side="bot")
b_ch   = block(10.6, RX_Y, 2.6, "u_ch_est",
               "channel_est\nSTREAM_MODE pilot eq", RX_COLOR,
               dbg_label="dbg_eq_valid", dbg_side="bot")
b_dmap = block(7.5,  RX_Y, 2.7, "u_rx_demap",
               "rx_subcarrier_demap\ndrop NULL/pilot → 48d", RX_COLOR)
b_dmod = block(4.4,  RX_Y, 2.7, "u_qpsk_demod",
               "qpsk_demod\nSCALE=7 LLR + sat8", RX_COLOR,
               dbg_label="dbg_demod_valid", dbg_side="bot")
b_llr  = block(1.4,  RX_Y, 2.6, "u_llr_buf",
               "llr_buffer\n1024 LLRs", RX_COLOR,
               dbg_label="dbg_llr_done", dbg_side="bot")

# RX wires (data flows right → left)
harrow(p_rxi[0],  b_cprm[2], RX_Y, "rx_iq",        "raw I/Q",       color="#A04400")
harrow(b_cprm[0], b_fft[2],  RX_Y, "cp_rem_tdata", "AXI-S 64/sym",  color="#A04400")
harrow(b_fft[0],  b_ch[2],   RX_Y, "fft_m_tdata",  "freq bins",     color="#A04400")
harrow(b_ch[0],   b_dmap[2], RX_Y, "eq_tdata",     "equalised I/Q", color="#A04400")
harrow(b_dmap[0], b_dmod[2], RX_Y, "demap_tdata",  "48 data/sym",   color="#A04400")
harrow(b_dmod[0], b_llr[2],  RX_Y, "demod_llr",    "8-bit signed",  color="#A04400")

# ---------------------------------------------------------------------------
# u_ldpc_dec drops below u_llr_buf  +  rx_decoded port  +  bus-debug pin
# ---------------------------------------------------------------------------
b_dec  = block(1.4, DEC_Y, 2.6, "u_ldpc_dec",
               "ldpc_decoder\nmin-sum BP, MAX_ITER=10", RX_COLOR)
varrow(b_llr[0] + (b_llr[2] - b_llr[0]) / 2,
       b_llr[1],  # bottom of u_llr_buf
       b_dec[3],  # top of u_ldpc_dec
       sig="1024 LLRs", color="#A04400")

p_rxo  = port_box(4.5, DEC_Y, 3.2,
                  "rx_decoded[511:0]\nrx_valid_out", h=1.45)
harrow(b_dec[2], p_rxo[0], DEC_Y, "decoded bits", "", color="#A04400")

# 512-bit hard-decision bus debug pin — attached above u_ldpc_dec
# (placed between u_llr_buf and u_ldpc_dec, sitting alongside the
# "1024 LLRs" vertical arrow so it never collides with the legend.)
dbg_pill_x = b_dec[2] + 0.25
dbg_pill_y = (b_llr[1] + b_dec[3]) / 2 - 0.22
ax.add_patch(patches.FancyBboxPatch(
    (dbg_pill_x, dbg_pill_y), 3.1, 0.46,
    boxstyle="round,pad=0.02", linewidth=0.9,
    edgecolor="#7A5C00", facecolor=DBG_COLOR))
ax.text(dbg_pill_x + 1.55, dbg_pill_y + 0.23,
        "dbg_chllr_decoded[511:0]",
        ha="center", va="center",
        fontsize=9, family="monospace", color="#5A4400")
# small leader from u_ldpc_dec right edge upward to the pill
ax.plot([b_dec[2], b_dec[2] + 0.2, dbg_pill_x],
        [b_dec[3] - 0.3, dbg_pill_y + 0.23, dbg_pill_y + 0.23],
        color="#B89500", lw=1.0, linestyle=(0, (4, 2)))

# ---------------------------------------------------------------------------
# Legend (bottom-left)
# ---------------------------------------------------------------------------
def lg_box(x, y, color, label, edgecolor="black"):
    ax.add_patch(patches.Rectangle((x, y), 0.6, 0.4,
                                   facecolor=color, edgecolor=edgecolor))
    ax.text(x + 0.78, y + 0.20, label, va="center", fontsize=10.5)

lg_y = 0.45
lg_box(0.55, lg_y, TX_COLOR, "TX submodule")
lg_box(3.50, lg_y, RX_COLOR, "RX submodule")
lg_box(6.55, lg_y, DBG_COLOR, "debug tap (yellow pill)", edgecolor="#7A5C00")
lg_box(11.0, lg_y, PORT_COLOR, "top-level port")

ax.text(W / 2, lg_y - 0.20,
        "Pipeline latencies — ldpc_enc 18 cy   |   IFFT 64 cy   |   "
        "+CP 16 sample   |   ldpc_decode ≈ 8200 cy   ·   fclk = 50 MHz",
        ha="center", fontsize=9.5, color="#444", style="italic")

out = "/home/ysara/fpga_hdl/simulation/rtl_ofdm_ldpc_top.png"
plt.savefig(out, dpi=140, bbox_inches="tight")
print(f"Saved {out}")
plt.close(fig)
