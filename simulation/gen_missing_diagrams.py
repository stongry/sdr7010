#!/usr/bin/env python3
"""Generate the 8 missing diagrams identified by inventory check."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

OUT = "/home/ysara/fpga_hdl/simulation"

# =============================================================================
# 1. OFDM 64-bin subcarrier layout
# =============================================================================
def make_ofdm_layout():
    fig, ax = plt.subplots(figsize=(20, 5))
    PILOTS = {7, 21, 43, 57}
    NULLS = {0} | set(range(27, 38))

    for k in range(64):
        if k in NULLS:
            color = "#888"; label = "NULL"; tcol = "white"
        elif k in PILOTS:
            color = "#FF6B6B"; label = "PILOT"; tcol = "white"
        else:
            color = "#4ECDC4"; label = "DATA"; tcol = "black"

        ax.add_patch(patches.Rectangle((k, 0), 1, 2, fc=color, ec="black", lw=0.8))
        ax.text(k + 0.5, 1.3, str(k), ha="center", va="center", fontsize=8, color=tcol, weight="bold")
        ax.text(k + 0.5, 0.6, label, ha="center", va="center", fontsize=6, color=tcol)

    # Annotations
    ax.text(32, 3.1, "DC", ha="center", fontsize=10, weight="bold")
    ax.annotate("", xy=(0.5, 2.0), xytext=(0.5, 2.7), arrowprops=dict(arrowstyle="->"))

    # Pilot markers
    for p in PILOTS:
        ax.text(p + 0.5, -0.5, "P", ha="center", fontsize=11, weight="bold", color="darkred")
    ax.text(60, -0.5, "P = pilot bin (k=7,21,43,57)", fontsize=9, color="darkred")

    # Counts
    ax.text(2, 2.6, "Counts:  DATA=48  •  PILOT=4  •  NULL=12  •  Total=64", fontsize=11, weight="bold")

    ax.set_xlim(-1, 65)
    ax.set_ylim(-1.5, 3.5)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title("OFDM 64-bin Subcarrier Layout (similar to IEEE 802.11a/g)",
                 fontsize=14, weight="bold")

    plt.savefig(f"{OUT}/ofdm_subcarrier_layout.png", dpi=120, bbox_inches="tight")
    print("Saved ofdm_subcarrier_layout.png")


# =============================================================================
# 2. QPSK constellation standalone
# =============================================================================
def make_qpsk_constellation():
    fig, ax = plt.subplots(figsize=(10, 10))
    A = 5793
    points = [
        (+A, +A, "00", "I=+A, Q=+A", "#1f77b4"),
        (+A, -A, "01", "I=+A, Q=-A", "#2ca02c"),
        (-A, +A, "10", "I=-A, Q=+A", "#d62728"),
        (-A, -A, "11", "I=-A, Q=-A", "#9467bd"),
    ]
    for ti, tq, bits, lbl, col in points:
        ax.scatter([ti], [tq], s=600, color=col, edgecolors="black", linewidth=2.5, zorder=10)
        ax.annotate(f"bits={bits}\n{lbl}",
                    (ti, tq), textcoords="offset points", xytext=(20, 20),
                    fontsize=12, color=col, weight="bold",
                    bbox=dict(boxstyle="round,pad=0.3", fc="white", ec=col, lw=1.5))

    # Quadrant labels
    ax.text(4500, 4500, "Q1\n(00)", fontsize=14, color="#1f77b4", alpha=0.4, ha="center", weight="bold")
    ax.text(4500, -4500, "Q4\n(01)", fontsize=14, color="#2ca02c", alpha=0.4, ha="center", weight="bold")
    ax.text(-4500, 4500, "Q2\n(10)", fontsize=14, color="#d62728", alpha=0.4, ha="center", weight="bold")
    ax.text(-4500, -4500, "Q3\n(11)", fontsize=14, color="#9467bd", alpha=0.4, ha="center", weight="bold")

    ax.axhline(0, color="gray", linewidth=0.6)
    ax.axvline(0, color="gray", linewidth=0.6)
    ax.set_xlim(-9000, 9000); ax.set_ylim(-9000, 9000)
    ax.set_xticks([-A, 0, A])
    ax.set_xticklabels([f"-A\n(-{A})", "0", f"+A\n(+{A})"])
    ax.set_yticks([-A, 0, A])
    ax.set_yticklabels([f"-A\n(-{A})", "0", f"+A\n(+{A})"])
    ax.set_xlabel("I  (in-phase, signed 16-bit)", fontsize=12)
    ax.set_ylabel("Q  (quadrature, signed 16-bit)", fontsize=12)
    ax.set_aspect("equal")
    ax.grid(True, linestyle=":", alpha=0.4)
    ax.set_title(f"QPSK Constellation (Gray-coded)\nA = {A} = ⌊8192 / √2⌋  ↔  Magnitude = A·√2 ≈ 8192 = 2¹³",
                 fontsize=14, weight="bold")

    # Distance annotation
    ax.annotate("", xy=(A, A), xytext=(A, -A),
                arrowprops=dict(arrowstyle="<->", color="orange", lw=1.5))
    ax.text(A + 200, 0, "Hamming dist = 1\n(only Q-bit flips)",
            fontsize=10, color="orange", style="italic")

    plt.savefig(f"{OUT}/qpsk_constellation.png", dpi=120, bbox_inches="tight")
    print("Saved qpsk_constellation.png")


# =============================================================================
# 3. LDPC base matrix H_b heatmap
# =============================================================================
def make_ldpc_hb():
    # Synthetic illustrative HB based on common (1024,512) IRA QC code structure
    # info part: 8x8 random shifts; parity part: dual-diagonal
    np.random.seed(42)
    Z = 64
    info_part = np.random.choice([Z+1] + list(range(Z)), size=(8, 8), p=[0.5] + [0.5/Z]*Z)
    parity_part = np.full((8, 8), Z+1)  # filler = invalid
    for i in range(8):
        parity_part[i, i] = 0
        if i + 1 < 8:
            parity_part[i + 1, i] = 0  # dual-diagonal

    HB = np.hstack([info_part, parity_part])

    fig, ax = plt.subplots(figsize=(16, 6))
    masked = np.ma.masked_where(HB > Z, HB)
    cmap = plt.get_cmap("viridis").copy()
    cmap.set_bad(color="white")
    im = ax.imshow(masked, cmap=cmap, vmin=0, vmax=Z-1, aspect="equal")
    cbar = plt.colorbar(im, ax=ax, fraction=0.025)
    cbar.set_label("cyclic shift value (0 to Z-1)", fontsize=10)

    for r in range(8):
        for c in range(16):
            v = HB[r, c]
            if v > Z:
                ax.text(c, r, "·", ha="center", va="center", fontsize=10, color="lightgray")
            else:
                ax.text(c, r, f"{v}", ha="center", va="center",
                        fontsize=8, color="white" if v < 32 else "black")

    # Mark info/parity regions
    ax.add_patch(patches.Rectangle((-0.5, -0.5), 8, 8, fill=False, ec="darkblue", lw=2.5, ls="--"))
    ax.add_patch(patches.Rectangle((7.5, -0.5), 8, 8, fill=False, ec="darkred", lw=2.5, ls="--"))
    ax.text(3.5, -1, "INFO part (k_bits → cw[511:0])", ha="center",
            fontsize=11, color="darkblue", weight="bold")
    ax.text(11.5, -1, "PARITY part (IRA dual-diagonal → cw[1023:512])",
            ha="center", fontsize=11, color="darkred", weight="bold")

    ax.set_xticks(range(16))
    ax.set_yticks(range(8))
    ax.set_xticklabels([f"col{c}" for c in range(16)], fontsize=8)
    ax.set_yticklabels([f"row{r}" for r in range(8)], fontsize=8)
    ax.set_title(f"LDPC Base Matrix H_b ({8}×{16}, lifting Z={Z})\n"
                 f"Each cell = circulant shift (0..{Z-1}) or zero block (·)\n"
                 f"Expanded H = {8*Z}×{16*Z} = 512×1024 sparse parity-check matrix",
                 fontsize=12, weight="bold")

    plt.savefig(f"{OUT}/ldpc_base_matrix.png", dpi=120, bbox_inches="tight")
    print("Saved ldpc_base_matrix.png")


# =============================================================================
# 4. BOOT.bin layout (byte-level partition map)
# =============================================================================
def make_bootbin_layout():
    fig, ax = plt.subplots(figsize=(20, 5))
    fig.suptitle("LDSDR Original BOOT.bin (1,488,916 bytes) — byte-level partition map",
                 fontsize=14, weight="bold")

    regions = [
        (0x000, 0x020, "ARM\nVector\n0..0x1F", "#FFE4E1"),
        (0x020, 0x024, "Magic\n0x665599AA", "#FFD700"),
        (0x024, 0x028, "XLNX", "#FFD700"),
        (0x028, 0x030, "Hdr ver", "#FFE4B5"),
        (0x030, 0x040, "FSBL\nsrc info\n(off+len)", "#90EE90"),
        (0x040, 0x048, "FSBL len", "#90EE90"),
        (0x048, 0x04C, "Hdr CRC", "#FFD700"),
        (0x04C, 0x098, "reserved", "#F5F5F5"),
        (0x098, 0x09C, "IHT off\n0x8C0", "#FFA07A"),
        (0x09C, 0x0A0, "PHT off\n0xC80", "#FFA07A"),
        (0x0A0, 0x8C0, "padding", "#F5F5F5"),
        (0x8C0, 0xC80, "Image\nHeader\nTable", "#FFA07A"),
        (0xC80, 0xCC0, "PHT P0\nFSBL", "#90EE90"),
        (0xCC0, 0xD00, "PHT P1\nbitstream", "#87CEEB"),
        (0xD00, 0xD40, "PHT P2\nu-boot", "#DDA0DD"),
        (0xD40, 0x1700, "padding", "#F5F5F5"),
        (0x1700, 0x19708, "FSBL\nELF body\n98,312 bytes", "#90EE90"),
        (0x19708, 0x1DFC8, "padding\n0xFF", "#F5F5F5"),
        (0x1DFC8, 0x10A508, "BITSTREAM\n968,000 bytes\n(byte-swapped)", "#87CEEB"),
        (0x10A508, 0x16B194, "U-BOOT\nELF body\n416,660 bytes", "#DDA0DD"),
    ]

    file_size = 1488916
    log_max = np.log10(file_size + 1)

    for start, end, label, color in regions:
        x_start = np.log10(start + 1) / log_max
        x_end = np.log10(end + 1) / log_max
        w = x_end - x_start
        ax.add_patch(patches.Rectangle((x_start, 0.2), w, 1.6, fc=color, ec="black", lw=0.8))
        ax.text(x_start + w/2, 1.0, label, ha="center", va="center", fontsize=8.5, weight="bold")
        # bottom: byte offsets
        ax.text(x_start, 0.05, f"0x{start:X}", fontsize=7, ha="left", color="black")

    ax.text(0.01, 2.1, "log scale (so small headers visible)", fontsize=8, color="gray", style="italic")
    ax.text(0.5, -0.2, "← BootROM Header → │ ← IHT/PHT → │ ← FSBL → │ ← Bitstream (PCAP via FSBL) → │ ← U-Boot → │",
            ha="center", fontsize=10, color="darkgreen", weight="bold")

    ax.set_xlim(0, 1)
    ax.set_ylim(-0.5, 2.3)
    ax.axis("off")

    plt.savefig(f"{OUT}/bootbin_layout.png", dpi=120, bbox_inches="tight")
    print("Saved bootbin_layout.png")


# =============================================================================
# 5. Test pyramid
# =============================================================================
def make_test_pyramid():
    fig, ax = plt.subplots(figsize=(14, 9))

    layers = [
        # (y_top, y_bot, x_half, label, color, count)
        (0.95, 0.80, 0.20, "Layer 4: Board RF end-to-end\n(path_x_v3.py over real AD9363)",            "#FF6B6B", "1"),
        (0.80, 0.60, 0.30, "Layer 3: PL real OFDM+LDPC on board\n(phase-2 build #9, xfft_v9.1 IP)",    "#FFA500", "partial"),
        (0.60, 0.35, 0.42, "Layer 2: Vivado xsim gate-level simulation\n(tb_path_x_simple.v, 3× repeats)", "#FFD700", "1"),
        (0.35, 0.05, 0.50, "Layer 1: Behavioural xsim full pipeline\n(tb_ofdm_ldpc.v, real DFT + LDPC + 0/512 errors)", "#90EE90", "1"),
    ]

    for y_top, y_bot, x_half, label, color, count in layers:
        # Trapezoid
        x_top = 0.5 - (x_half * y_top)
        x_top_r = 0.5 + (x_half * y_top)
        x_bot = 0.5 - (x_half * y_bot)
        x_bot_r = 0.5 + (x_half * y_bot)
        # Use polygon
        poly = patches.Polygon(
            [[0.5 - x_half * y_top, y_top],
             [0.5 + x_half * y_top, y_top],
             [0.5 + x_half * y_bot, y_bot],
             [0.5 - x_half * y_bot, y_bot]],
            closed=True, fc=color, ec="black", lw=1.5)
        ax.add_patch(poly)
        ax.text(0.5, (y_top + y_bot) / 2, label,
                ha="center", va="center", fontsize=11, weight="bold", color="black")

    # Side annotations
    ax.text(0.04, 0.875, "Slowest, hardest to debug\nbut highest fidelity",
            ha="left", va="center", fontsize=9, color="darkred", style="italic")
    ax.text(0.96, 0.875, "PASS\n0/32 errors\nover RF",
            ha="right", va="center", fontsize=9, color="darkred", weight="bold",
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="darkred"))

    ax.text(0.04, 0.20, "Fastest, easiest to iterate\nlower fidelity",
            ha="left", va="center", fontsize=9, color="darkgreen", style="italic")
    ax.text(0.96, 0.50, "PASS\n0/32 errors\n(3× repeats)",
            ha="right", va="center", fontsize=9, color="darkorange", weight="bold",
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="darkorange"))
    # Layer 3 phase-2: rx_done=1 but pass_flag=0 (raw 6-12 bit residual,
    # IP numeric precision limit, see lkh.md §35)
    ax.text(0.96, 0.70, "PARTIAL\nrx_done=1\npass_flag=0\n(IP precision)",
            ha="right", va="center", fontsize=9, color="darkorange", weight="bold",
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="darkorange"))
    # Layer 1 phase-1 PASS message
    ax.text(0.96, 0.20, "PASS\n0/512 errors\n(real DFT cascade)",
            ha="right", va="center", fontsize=9, color="darkgreen", weight="bold",
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="darkgreen"))

    ax.set_xlim(0, 1); ax.set_ylim(0, 1.05)
    ax.axis("off")
    ax.set_title("SDR7010 — Verification Pyramid (4 layers)\n"
                 "Layers 1/2/4 PASS, Layer 3 partial (real OFDM+LDPC on board, "
                 "rx_done=1 but pass_flag=0 — IP numeric precision)",
                 fontsize=12, weight="bold")

    plt.savefig(f"{OUT}/test_pyramid.png", dpi=120, bbox_inches="tight")
    print("Saved test_pyramid.png")


# =============================================================================
# 6. AD9363 LVDS pin map (LDSDR clg400)
# =============================================================================
def make_ad9363_pinmap():
    fig, ax = plt.subplots(figsize=(16, 9))

    pins = [
        # (name, fpga_pin, group, color)
        ("rx_clk_in_p",   "N20", "RX clk", "#FFE4B5"),
        ("rx_clk_in_n",   "P20", "RX clk", "#FFE4B5"),
        ("rx_frame_p",    "Y16", "RX frame", "#FFE4B5"),
        ("rx_frame_n",    "Y17", "RX frame", "#FFE4B5"),
        ("rx_data_p[0]",  "Y18", "RX data 0", "#90EE90"),
        ("rx_data_n[0]",  "Y19", "RX data 0", "#90EE90"),
        ("rx_data_p[1]",  "V17", "RX data 1", "#90EE90"),
        ("rx_data_n[1]",  "V18", "RX data 1", "#90EE90"),
        ("rx_data_p[2]",  "W18", "RX data 2", "#90EE90"),
        ("rx_data_n[2]",  "W19", "RX data 2", "#90EE90"),
        ("rx_data_p[3]",  "R16", "RX data 3", "#90EE90"),
        ("rx_data_n[3]",  "R17", "RX data 3", "#90EE90"),
        ("rx_data_p[4]",  "V20", "RX data 4", "#90EE90"),
        ("rx_data_n[4]",  "W20", "RX data 4", "#90EE90"),
        ("rx_data_p[5]",  "W14", "RX data 5", "#90EE90"),
        ("rx_data_n[5]",  "Y14", "RX data 5", "#90EE90"),
        ("tx_clk_p",      "N18", "TX clk",  "#FFE4E1"),
        ("tx_clk_n",      "P19", "TX clk",  "#FFE4E1"),
        ("tx_frame_p",    "V16", "TX frame", "#FFE4E1"),
        ("tx_frame_n",    "W16", "TX frame", "#FFE4E1"),
        ("tx_data_p[0]",  "T16", "TX data 0", "#87CEEB"),
        ("tx_data_n[0]",  "U17", "TX data 0", "#87CEEB"),
        ("tx_data_p[1]",  "U18", "TX data 1", "#87CEEB"),
        ("tx_data_n[1]",  "U19", "TX data 1", "#87CEEB"),
        ("tx_data_p[2]",  "U14", "TX data 2", "#87CEEB"),
        ("tx_data_n[2]",  "U15", "TX data 2", "#87CEEB"),
        ("tx_data_p[3]",  "V12", "TX data 3", "#87CEEB"),
        ("tx_data_n[3]",  "W13", "TX data 3", "#87CEEB"),
        ("tx_data_p[4]",  "T12", "TX data 4", "#87CEEB"),
        ("tx_data_n[4]",  "U12", "TX data 4", "#87CEEB"),
        ("tx_data_p[5]",  "V15", "TX data 5", "#87CEEB"),
        ("tx_data_n[5]",  "W15", "TX data 5", "#87CEEB"),
        ("spi_csn",       "T20", "SPI",     "#DDA0DD"),
        ("spi_clk",       "R19", "SPI",     "#DDA0DD"),
        ("spi_mosi",      "P18", "SPI",     "#DDA0DD"),
        ("spi_miso",      "T19", "SPI",     "#DDA0DD"),
        ("en_agc",        "P16", "ctrl",    "#F0E68C"),
        ("resetb",        "T17", "ctrl",    "#F0E68C"),
        ("enable",        "R18", "ctrl",    "#F0E68C"),
        ("txnrx",         "N17", "ctrl",    "#F0E68C"),
    ]

    # Layout in 3 columns
    cols = [pins[:14], pins[14:30], pins[30:]]
    col_x = [0.5, 6.5, 12.5]
    col_w = 5.5

    for col_idx, col_pins in enumerate(cols):
        x = col_x[col_idx]
        for i, (name, fpga, group, color) in enumerate(col_pins):
            y = 8 - i * 0.55
            ax.add_patch(patches.Rectangle((x, y), col_w, 0.4, fc=color, ec="black", lw=0.6))
            ax.text(x + 0.15, y + 0.2, name, ha="left", va="center", fontsize=9, family="monospace")
            ax.text(x + col_w - 0.15, y + 0.2, fpga, ha="right", va="center",
                    fontsize=9, family="monospace", weight="bold", color="darkred")

    # Legend
    legend_y = 8.7
    legend_items = [
        ("LVDS_25 RX",  "#90EE90", 0.5),
        ("LVDS_25 TX",  "#87CEEB", 4),
        ("LVDS_25 clk/frame", "#FFE4B5", 7.5),
        ("LVCMOS25 SPI",  "#DDA0DD", 11.5),
        ("LVCMOS25 ctrl", "#F0E68C", 15.0),
    ]
    for label, color, x in legend_items:
        ax.add_patch(patches.Rectangle((x, legend_y), 0.4, 0.3, fc=color, ec="black"))
        ax.text(x + 0.5, legend_y + 0.15, label, va="center", fontsize=9)

    ax.set_xlim(0, 18.5); ax.set_ylim(-0.5, 9.3)
    ax.axis("off")
    ax.set_title("AD9363 ↔ Zynq xc7z010clg400 Pin Map (LDSDR rev2.1)\n"
                 "16 LVDS pairs (RX 8 + TX 8) + 4 SPI + 4 control",
                 fontsize=14, weight="bold")

    plt.savefig(f"{OUT}/ad9363_pinmap.png", dpi=120, bbox_inches="tight")
    print("Saved ad9363_pinmap.png")


# =============================================================================
# 7. cp_insert ping-pong FSM
# =============================================================================
def make_cp_insert_fsm():
    fig, ax = plt.subplots(figsize=(13, 8))
    states = [
        (3, 5, "INIT\n bank_sel=0\n cnt=0", "#FFE4E1"),
        (10, 5, "FILL_A\n write bank_A[cnt]\n cnt=0..63",  "#90EE90"),
        (10, 1, "FLUSH_A\n read bank_A[cnt]\n CP from idx 48..63\n then 0..63", "#87CEEB"),
        (3, 1, "FILL_B\n write bank_B[cnt]\n simultaneously", "#FFE4B5"),
    ]
    for x, y, label, color in states:
        ax.add_patch(patches.FancyBboxPatch((x-1.5, y-0.7), 3, 1.4,
                                             boxstyle="round,pad=0.1",
                                             fc=color, ec="black", lw=2))
        ax.text(x, y, label, ha="center", va="center", fontsize=10, weight="bold")

    arrows = [
        (3, 5.8, 10, 5.8, "valid_in"),
        (10, 4.3, 10, 1.7, "cnt==63 ⇒ start output"),
        (10, 1, 3.5, 1, "swap banks"),
        (3, 1.7, 3, 4.3, "next symbol"),
    ]
    for x1, y1, x2, y2, label in arrows:
        ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                    arrowprops=dict(arrowstyle="->", color="black", lw=1.6))
        ax.text((x1+x2)/2, (y1+y2)/2 + 0.15, label,
                fontsize=8, ha="center", style="italic", color="darkblue",
                bbox=dict(boxstyle="round,pad=0.1", fc="white", ec="none"))

    ax.set_xlim(0, 14); ax.set_ylim(-0.5, 7)
    ax.axis("off")
    ax.set_title("cp_insert FSM — ping-pong buffer architecture\n"
                 "(input: 64 sample/symbol  →  output: 80 sample/symbol with prefix)",
                 fontsize=13, weight="bold")
    plt.savefig(f"{OUT}/fsm_cp_insert.png", dpi=120, bbox_inches="tight")
    print("Saved fsm_cp_insert.png")


# =============================================================================
# 8. ldpc_decoder FSM
# =============================================================================
def make_ldpc_decoder_fsm():
    fig, ax = plt.subplots(figsize=(15, 8))
    states = [
        (2, 5, "ST_IDLE",                                                 "#F5F5F5"),
        (5.5, 5, "ST_INIT\n• read 1024 LLR\n• write msg_cv=0\n• 8192 cy",  "#FFE4B5"),
        (9.5, 5, "ST_VC_UPDATE\n• v_llr = ch_llr - Σmsg_cv + msg_self\n• 1024 cy", "#90EE90"),
        (13.5, 5, "ST_CV_UPDATE\n• min-sum: m_cv = sign(prod) * min|m_vc|\n• 1024 cy", "#87CEEB"),
        (9.5, 1.5, "ST_HD_CHECK\n• hard decision\n• verify Hc=0",          "#DDA0DD"),
        (5.5, 1.5, "ST_OUT\n• decoded[511:0] = info part\n• valid_out=1",  "#FFB6C1"),
    ]
    for x, y, label, color in states:
        w = 3.0; h = 1.5
        ax.add_patch(patches.FancyBboxPatch((x-w/2, y-h/2), w, h,
                                             boxstyle="round,pad=0.1",
                                             fc=color, ec="black", lw=1.8))
        ax.text(x, y, label, ha="center", va="center", fontsize=9, weight="bold")

    arrows = [
        (3.5, 5, 4, 5, "valid_in"),
        (7, 5, 8, 5, "8192 cycles done"),
        (11, 5, 12, 5, "after VC"),
        (13.5, 4.25, 11, 2.25, "iter complete"),
        (8, 1.5, 7, 1.5, "Hc=0 (success)"),
        (5.5, 2.25, 8, 4.25, "Hc≠0\niter < MAX"),
        (4, 5, 4, 1.5, "iter == MAX (give up)\n→ output anyway"),
    ]
    for x1, y1, x2, y2, label in arrows:
        ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                    arrowprops=dict(arrowstyle="->", color="black", lw=1.4))
        ax.text((x1+x2)/2, (y1+y2)/2 + 0.18, label, fontsize=8,
                ha="center", style="italic", color="darkred",
                bbox=dict(boxstyle="round,pad=0.1", fc="white", ec="none", alpha=0.8))

    ax.text(0.5, 7.5,
            "MAX_ITER=10  •  Q=8 (8-bit signed LLR)  •  Worst case ~10240 cycles ≈ 200 µs @ 50 MHz",
            fontsize=10, weight="bold", color="darkblue")
    ax.text(0.5, 6.8,
            "Distinguishing feature: ST_INIT also captures dbg_chllr_decoded[K-1:0] (raw hard decision)\n"
            "→ This is what `ofdm_ldpc_pl` checks against TEST_BITS for pass_flag, BYPASSING BP entirely",
            fontsize=9, color="darkgreen", style="italic")

    ax.set_xlim(0, 16); ax.set_ylim(0, 8.5)
    ax.axis("off")
    ax.set_title("ldpc_decoder FSM — min-sum BP with hard-decision early-exit",
                 fontsize=13, weight="bold")
    plt.savefig(f"{OUT}/fsm_ldpc_decoder.png", dpi=120, bbox_inches="tight")
    print("Saved fsm_ldpc_decoder.png")


# =============================================================================
# 9. Path X software OFDM pipeline
# =============================================================================
def make_path_x_pipeline():
    fig, ax = plt.subplots(figsize=(20, 10))

    boxes_tx = [
        (0.5, 7, 2.5, 1.4, "TEST_BITS_LO\n0x0F0F0F0F", "#FFFFFF"),
        (3.5, 7, 2.5, 1.4, "build_symbol()\nQPSK + IFFT(64) + CP(16)\n→ 80 complex samples", "#90EE90"),
        (6.5, 7, 2.5, 1.4, "scale = 28000 / max_amp\nint16 (12-bit DAC range)", "#FFE4B5"),
        (9.5, 7, 3.0, 1.4, "iio.Buffer(txdev, 5120, cyclic=True)\nbuf.write(packed_iq).push()", "#FFB6C1"),
        (13.0, 7, 2.5, 1.4, "axi_dmac TX → cf-ad9361-dds-core-lpc\n→ AD9363 LVDS DAC", "#87CEEB"),
        (16.0, 7, 3.0, 1.4, "RF: TX1 → SMA → RX1\nLO=2.4 GHz, fs=2.5 MHz, ATT=-75 dB\n(safe: -69 dBm)", "#FFE4E1"),
    ]

    boxes_rx = [
        (16.0, 4, 3.0, 1.4, "AD9363 LVDS ADC\nrxgain=30 dB manual", "#87CEEB"),
        (13.0, 4, 2.5, 1.4, "axi_dmac RX → cf-ad9361-lpc\n→ kernel DMA buffer", "#FFB6C1"),
        (9.5, 4, 3.0, 1.4, "iio.Buffer(rxdev, 8192, cyclic=False)\nbuf.refill().read() → np.int16", "#FFE4B5"),
        (6.5, 4, 2.5, 1.4, "CP autocorrelation sync\nargmax of |Σ conj(x[k:k+N_CP])\n × x[k+N_FFT:...]|", "#90EE90"),
        (3.5, 4, 2.5, 1.4, "FFT(rx[sym_start:sym_start+64])\n+ demap 48 data bins\n+ QPSK hard decision", "#90EE90"),
        (0.5, 4, 2.5, 1.4, "decoded[31:0]\n0x0F0F0F0F\n0/32 errors ✓ PASS", "#FAFAD2"),
    ]

    for x, y, w, h, label, color in boxes_tx + boxes_rx:
        ax.add_patch(patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05",
                                             fc=color, ec="black", lw=1.4))
        ax.text(x + w/2, y + h/2, label, ha="center", va="center", fontsize=9, weight="bold")

    # Arrows TX
    for i in range(5):
        x1 = 0.5 + i*3 + (2.5 if i == 3 else 2.5)
        if i == 3: x1 = 12.5
        x2 = x1 + (1 if i < 3 else 0.5)
        ax.annotate("", xy=(x2, 7.7), xytext=(x1, 7.7),
                    arrowprops=dict(arrowstyle="->", color="black", lw=1.5))

    # turn down
    ax.annotate("", xy=(17.5, 5.4), xytext=(17.5, 7.0),
                arrowprops=dict(arrowstyle="->", color="darkred", lw=2))
    ax.text(18.0, 6.2, "RF\nself-loop", fontsize=9, color="darkred", style="italic", weight="bold")

    # Arrows RX
    for i in range(5):
        x1 = 16.0 - i * 3 + (0 if i == 0 else 0)
        x_starts = [16.0, 13.0, 9.5, 6.5, 3.5]
        x_ends   = [13.0+2.5, 9.5+3.0, 6.5+2.5, 3.5+2.5, 0.5+2.5]
        if i == 0:
            x1, x2 = 16.0, 15.5
        elif i == 1:
            x1, x2 = 13.0, 12.5
        elif i == 2:
            x1, x2 = 9.5, 9.0
        elif i == 3:
            x1, x2 = 6.5, 6.0
        elif i == 4:
            x1, x2 = 3.5, 3.0
        ax.annotate("", xy=(x2, 4.7), xytext=(x1, 4.7),
                    arrowprops=dict(arrowstyle="->", color="black", lw=1.5))

    # Title bands
    ax.text(0.5, 8.7, "TX PATH (Python → DMA → AD9363 → RF)", fontsize=12, weight="bold", color="darkred",
            bbox=dict(boxstyle="round,pad=0.3", fc="#FFE4E1", ec="darkred"))
    ax.text(0.5, 5.7, "RX PATH (RF → AD9363 → DMA → numpy → bits)", fontsize=12, weight="bold", color="darkblue",
            bbox=dict(boxstyle="round,pad=0.3", fc="#E0F0FF", ec="darkblue"))

    # Stats
    ax.text(10, 1.5,
            "Best operating point  rxgain=30 dB  •  RMS=3.5  •  sync_offset=-1 sample\n"
            "Decoded bits:  0x0F0F0F0F  vs  TEST_BITS_LO=0x0F0F0F0F  →  0/32 mismatches ✓",
            ha="center", fontsize=11, weight="bold",
            bbox=dict(boxstyle="round,pad=0.4", fc="#A5D6A7", ec="darkgreen", lw=2))

    ax.set_xlim(0, 20); ax.set_ylim(0, 9.5)
    ax.axis("off")
    ax.set_title("Path X — Software OFDM Pipeline (path_x_v3.py end-to-end)",
                 fontsize=14, weight="bold")

    plt.savefig(f"{OUT}/path_x_pipeline.png", dpi=120, bbox_inches="tight")
    print("Saved path_x_pipeline.png")


if __name__ == "__main__":
    make_ofdm_layout()
    make_qpsk_constellation()
    make_ldpc_hb()
    make_bootbin_layout()
    make_test_pyramid()
    make_ad9363_pinmap()
    make_cp_insert_fsm()
    make_ldpc_decoder_fsm()
    make_path_x_pipeline()
    print("\nAll 9 missing diagrams generated.")
