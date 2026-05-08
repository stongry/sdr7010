#!/usr/bin/env python3
"""
Hierarchical RTL block diagram for ofdm_ldpc_top.

Layout (y-axis 0..20):
  19.0  title
  18.4  subtitle
  17.4  TX DATAPATH header
  16.0  TX yellow debug pills (above TX boxes)
  14.0..15.4  TX module row
  13.4  TX arrow row (inside the band)
  11.0..14.0  loop-back box on right
  10.0  RX DATAPATH header
  6.5..7.9   RX module row
  5.5   RX yellow debug pills below
  3.0..4.3  u_llr_buf  (lower-left)
  3.0..4.3  u_ldpc_dec to its right, then rx_decoded port further right
  1.5..2.1  dbg_chllr_decoded pill
  0.4..0.9  legend
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(24, 16))
ax.set_xlim(0, 24)
ax.set_ylim(0, 20)
ax.axis("off")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def box(x, y, w, h, label, color, sub=""):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.06",
        linewidth=1.6, edgecolor="black", facecolor=color))
    ax.text(x + w / 2, y + h * 0.62, label,
            ha="center", va="center", fontsize=12, weight="bold")
    if sub:
        ax.text(x + w / 2, y + h * 0.27, sub,
                ha="center", va="center", fontsize=9.5, style="italic")


def port_box(x, y, w, h, label):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.06",
        linewidth=1.4, edgecolor="black", facecolor="white"))
    ax.text(x + w / 2, y + h / 2, label,
            ha="center", va="center", fontsize=10.5, family="monospace")


def yellow_pill(x, y, w, h, label):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.05",
        linewidth=1.2, edgecolor="#b8860b", facecolor="#FFF3C0"))
    ax.text(x + w / 2, y + h / 2, label,
            ha="center", va="center", fontsize=10,
            family="monospace", color="#704800")


def harrow(x1, x2, y, top_label="", bot_label="", color="black"):
    """
    Horizontal arrow + labels offset above and below the arrow line.
    Labels carry an opaque white bbox so the arrow tail/head never bleeds
    through letters.
    """
    ax.annotate("", xy=(x2, y), xytext=(x1, y),
                arrowprops=dict(arrowstyle="->", color=color, lw=1.7))
    if top_label:
        ax.text((x1 + x2) / 2, y + 0.30, top_label,
                ha="center", va="center", fontsize=9.5,
                family="monospace", color="#222",
                bbox=dict(boxstyle="round,pad=0.20",
                          fc="white", ec="#777", lw=0.6))
    if bot_label:
        ax.text((x1 + x2) / 2, y - 0.30, bot_label,
                ha="center", va="center", fontsize=9,
                style="italic", color="#444",
                bbox=dict(boxstyle="round,pad=0.18",
                          fc="white", ec="none"))


# ---------------------------------------------------------------------------
# Title
# ---------------------------------------------------------------------------
ax.text(12, 19.30,
        "ofdm_ldpc_top  —  hierarchical RTL block diagram",
        ha="center", fontsize=20, weight="bold")
ax.text(12, 18.65,
        "blue = TX submodules,   orange = RX submodules,   "
        "yellow pill = EMIO debug tap (matches ofdm_ldpc_top.v)   "
        "—   clk / rst_n fan-out to all blocks (not drawn)",
        ha="center", fontsize=11, style="italic", color="dimgray")

# ---------------------------------------------------------------------------
# TX header (own row, no overlap with debug pills)
# ---------------------------------------------------------------------------
ax.text(0.4, 17.60, "TX  DATAPATH",
        fontsize=14, weight="bold", color="#1f3a93")
ax.text(4.6, 17.60, "encode → map → IFFT → CP-insert → DAC",
        fontsize=12.5, weight="bold", color="#1f3a93")

# Debug pills row (TX) — sits below the header, above the boxes
yellow_pill(3.75,  16.55, 2.1, 0.55, "dbg_enc_valid")
yellow_pill(10.55, 16.55, 1.7, 0.55, "dbg_ifft_valid")

# TX module row
TX_Y, TX_H = 14.4, 1.5
ARR_Y_TX = TX_Y + TX_H / 2

port_box(0.4, TX_Y + 0.15, 2.4, TX_H - 0.30,
         "tx_info_bits[511:0]\ntx_valid_in")
box(3.7, TX_Y, 2.2, TX_H, "u_ldpc_enc", "#CFE0F4",
    "ldpc_encoder\n(1024,512) IRA QC")
box(7.1, TX_Y, 2.2, TX_H, "u_tx_map", "#CFE0F4",
    "tx_subcarrier_map\n48d + 4p + 12N")
box(10.5, TX_Y, 1.8, TX_H, "u_ifft", "#CFE0F4",
    "xfft_stub (IFFT)\n64-pt complex")
box(13.5, TX_Y, 2.0, TX_H, "u_cp_ins", "#CFE0F4",
    "cp_insert\nCP=16, ping-pong")
port_box(16.7, TX_Y + 0.15, 2.7, TX_H - 0.30,
         "tx_iq_i [15:0]\ntx_iq_q [15:0]\ntx_valid_out")

# TX arrows  (gaps widened to 1.2 axis units so caption pills fit cleanly)
harrow(2.8, 3.7,  ARR_Y_TX, "valid_in",     "1 pulse / block")
harrow(5.9, 7.1,  ARR_Y_TX, "enc_codeword", "1024 bits")
harrow(9.3, 10.5, ARR_Y_TX, "ifft_s_tdata", "(I,Q) freq")
harrow(12.3, 13.5, ARR_Y_TX, "ifft_m_tdata", "(I,Q) time")
harrow(15.5, 16.7, ARR_Y_TX, "cp_ins_tdata", "+CP, 80/sym")

# ---------------------------------------------------------------------------
# Loopback box (between TX and RX rows, far right)
# ---------------------------------------------------------------------------
LB_X, LB_Y, LB_W, LB_H = 19.6, 9.6, 4.0, 4.6
ax.add_patch(patches.FancyBboxPatch(
    (LB_X, LB_Y), LB_W, LB_H, boxstyle="round,pad=0.06",
    linewidth=1.7, edgecolor="#1f7a1f", facecolor="#D8F0D8"))
ax.text(LB_X + LB_W / 2, LB_Y + LB_H * 0.66,
        "DIGITAL  LOOP-BACK",
        ha="center", fontsize=13, weight="bold", color="#0f5a0f")
ax.text(LB_X + LB_W / 2, LB_Y + LB_H * 0.36,
        "wire (Path X simulation)\n/   AD9363 + SMA  (Path A board)",
        ha="center", fontsize=10, style="italic", color="#0f5a0f")

# tx_iq port -> loopback (right then down)
ax.annotate("", xy=(LB_X + LB_W * 0.5, LB_Y + LB_H),
            xytext=(19.4, ARR_Y_TX - 0.15),
            arrowprops=dict(arrowstyle="->", color="black", lw=1.7,
                            connectionstyle="angle,angleA=0,angleB=90,rad=0"))
# Place caption above the horizontal arrow segment, OUTSIDE the loopback box
ax.text((19.4 + (LB_X + LB_W * 0.5)) / 2, ARR_Y_TX + 0.32,
        "tx_iq", fontsize=10.5, family="monospace",
        bbox=dict(boxstyle="round,pad=0.20",
                  fc="white", ec="#777", lw=0.5))

# ---------------------------------------------------------------------------
# RX header
# ---------------------------------------------------------------------------
ax.text(0.4, 9.10, "RX  DATAPATH",
        fontsize=14, weight="bold", color="#a04a00")
ax.text(4.6, 9.10,
        "CP-remove → FFT → channel-est → demap → demod → LLR → LDPC decode",
        fontsize=12.5, weight="bold", color="#a04a00")

# RX module row
RX_Y, RX_H = 6.9, 1.5
ARR_Y_RX = RX_Y + RX_H / 2

# Taller port box so its 3 lines of text aren't crowded into the arrow band
port_box(16.7, RX_Y - 0.35, 2.7, RX_H + 0.30,
         "rx_iq_i [15:0]\nrx_iq_q [15:0]\nrx_valid_in / rx_frame_start")
box(13.5, RX_Y, 2.0, RX_H, "u_cp_rem", "#FCD8C2",
    "cp_remove\nframe_start sync")
box(10.5, RX_Y, 1.8, RX_H, "u_fft", "#FCD8C2",
    "xfft_stub (FFT)\n64-pt")
box(7.1,  RX_Y, 2.2, RX_H, "u_ch_est", "#FCD8C2",
    "channel_est\nSTREAM_MODE pilot eq")
box(3.7,  RX_Y, 2.2, RX_H, "u_rx_demap", "#FCD8C2",
    "rx_subcarrier_demap\ndrop NULL/pilot → 48d")
box(0.4,  RX_Y, 2.2, RX_H, "u_qpsk_demod", "#FCD8C2",
    "qpsk_demod\nSCALE=7 LLR + sat8")

# RX arrows go right -> left (gaps widened to 1.1-1.2 so caption pills fit)
harrow(16.7, 15.5, ARR_Y_RX, "rx_iq",        "raw I/Q",        color="#5b3a00")
harrow(13.5, 12.3, ARR_Y_RX, "cp_rem_tdata", "AXI-S 64/sym",   color="#5b3a00")
harrow(10.5,  9.3, ARR_Y_RX, "fft_m_tdata",  "freq bins",      color="#5b3a00")
harrow(7.1,   5.9, ARR_Y_RX, "eq_tdata",     "equalised I/Q",  color="#5b3a00")
harrow(3.7,   2.6, ARR_Y_RX, "demap_tdata",  "48 data/sym",    color="#5b3a00")

# Debug pills below RX (dbg_demod_valid moved RIGHT so it never sits on
# the qpsk_demod -> llr_buf down-arrow column)
yellow_pill(13.55, 5.85, 1.9, 0.55, "dbg_cp_rem_valid")
yellow_pill(10.55, 5.85, 1.7, 0.55, "dbg_fft_m_valid")
yellow_pill(7.25,  5.85, 1.9, 0.55, "dbg_eq_valid")
yellow_pill(3.85,  5.85, 1.9, 0.55, "dbg_demod_valid")

# loopback -> rx_iq port (down then left)
ax.annotate("", xy=(18.0, RX_Y + RX_H + 0.25),
            xytext=(LB_X + LB_W * 0.5, LB_Y),
            arrowprops=dict(arrowstyle="->", color="black", lw=1.7,
                            connectionstyle="angle,angleA=-90,angleB=180,rad=0"))
ax.text(19.5, (LB_Y + RX_Y + RX_H) / 2,
        "rx_iq", fontsize=10.5, family="monospace",
        bbox=dict(boxstyle="round,pad=0.20",
                  fc="white", ec="#777", lw=0.5))

# ---------------------------------------------------------------------------
# u_llr_buf -> u_ldpc_dec -> rx_decoded
# ---------------------------------------------------------------------------
LLR_X, LLR_Y, LLR_W, LLR_H = 0.4, 3.4, 2.2, 1.4
box(LLR_X, LLR_Y, LLR_W, LLR_H, "u_llr_buf", "#FCD8C2",
    "llr_buffer\n1024 LLRs")

# Down arrow from u_qpsk_demod to u_llr_buf
ax.annotate("", xy=(LLR_X + LLR_W / 2, LLR_Y + LLR_H),
            xytext=(LLR_X + LLR_W / 2, RX_Y),
            arrowprops=dict(arrowstyle="->", color="#5b3a00", lw=1.7))
ax.text(LLR_X + LLR_W / 2 + 0.20, (LLR_Y + LLR_H + RX_Y) / 2,
        "demod_llr  (8-bit signed)",
        fontsize=9.5, style="italic", color="#5b3a00",
        ha="left", va="center",
        bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="none"))

# dbg_llr_done pill — placed BELOW u_llr_buf so it does not collide with
# the u_llr_buf -> u_ldpc_dec arrow or its "1024 LLRs" caption.
yellow_pill(LLR_X + 0.25, LLR_Y - 0.75, 1.7, 0.55, "dbg_llr_done")

LDP_X, LDP_Y, LDP_W, LDP_H = 6.0, 3.4, 2.6, 1.4
box(LDP_X, LDP_Y, LDP_W, LDP_H, "u_ldpc_dec", "#FCD8C2",
    "ldpc_decoder\nmin-sum BP, MAX_ITER=10")

ax.annotate("", xy=(LDP_X, LDP_Y + LDP_H * 0.5),
            xytext=(LLR_X + LLR_W, LLR_Y + LLR_H * 0.5),
            arrowprops=dict(arrowstyle="->", color="#5b3a00", lw=1.7))
ax.text((LLR_X + LLR_W + LDP_X) / 2, LLR_Y + LLR_H * 0.5 + 0.30,
        "1024 LLRs", fontsize=9.5, style="italic", color="#5b3a00",
        ha="center",
        bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="none"))

# rx_decoded port
RXD_X, RXD_Y, RXD_W, RXD_H = 10.5, 3.5, 3.0, 1.2
port_box(RXD_X, RXD_Y, RXD_W, RXD_H,
         "rx_decoded[511:0]\nrx_valid_out")

ax.annotate("", xy=(RXD_X, RXD_Y + RXD_H / 2),
            xytext=(LDP_X + LDP_W, LDP_Y + LDP_H / 2),
            arrowprops=dict(arrowstyle="->", color="#5b3a00", lw=1.7))
ax.text((LDP_X + LDP_W + RXD_X) / 2,
        (LDP_Y + LDP_H / 2) + 0.28,
        "decoded bits", fontsize=9.5, family="monospace",
        color="#5b3a00", ha="center",
        bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="#777", lw=0.5))

# Dashed line: u_ldpc_dec -> dbg_chllr_decoded pill.  Route below the
# u_ldpc_dec/rx_decoded row, then terminate at the pill's LEFT edge so it
# doesn't cross any pill text.
DBG_PILL_X, DBG_PILL_Y, DBG_PILL_W, DBG_PILL_H = 15.0, 2.45, 4.4, 0.65
yellow_pill(DBG_PILL_X, DBG_PILL_Y, DBG_PILL_W, DBG_PILL_H,
            "dbg_chllr_decoded[511:0]")
DASH_Y = DBG_PILL_Y + DBG_PILL_H * 0.5
ax.plot([LDP_X + LDP_W * 0.5,
         LDP_X + LDP_W * 0.5,
         DBG_PILL_X],
        [LDP_Y,
         DASH_Y,
         DASH_Y],
        linestyle="--", color="#b8860b", lw=1.4)
# Small arrow head at the pill edge so the connection direction reads.
ax.annotate("", xy=(DBG_PILL_X, DASH_Y),
            xytext=(DBG_PILL_X - 0.30, DASH_Y),
            arrowprops=dict(arrowstyle="->", color="#b8860b",
                            lw=1.4, linestyle="--"))
ax.text((LDP_X + LDP_W * 0.5 + DBG_PILL_X) / 2,
        DASH_Y + 0.30,
        "ST_INIT raw hard-decision",
        fontsize=9, style="italic", color="#704800",
        ha="center", va="center",
        bbox=dict(boxstyle="round,pad=0.20", fc="white", ec="none"))

# ---------------------------------------------------------------------------
# Legend (own row, well below everything else)
# ---------------------------------------------------------------------------
LG_Y = 1.20

def legend_swatch(x, color, label, edge="black"):
    ax.add_patch(patches.Rectangle((x, LG_Y), 0.60, 0.40,
                                   facecolor=color,
                                   edgecolor=edge, linewidth=1.0))
    ax.text(x + 0.78, LG_Y + 0.20, label,
            fontsize=11, va="center")


legend_swatch(0.4,  "#CFE0F4", "TX submodule")
legend_swatch(4.0,  "#FCD8C2", "RX submodule")
legend_swatch(7.6,  "#FFF3C0", "debug tap (yellow pill)", edge="#b8860b")
legend_swatch(13.0, "white",   "top-level port")

# Pipeline latency caption (separate line, very bottom)
ax.text(12, 0.40,
        "Pipeline latencies:  ldpc_enc 18 cy   |   IFFT 64 cy   |   "
        "+CP 16 sample   |   ldpc_decode ≈ 8200 cy        ·        fclk = 50 MHz",
        ha="center", fontsize=10.5, style="italic", color="dimgray")

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
out = "/home/ysara/fpga_hdl/simulation/rtl_ofdm_ldpc_top.png"
plt.savefig(out, dpi=140, bbox_inches="tight")
print(f"Saved {out}")
