#!/usr/bin/env python3
"""
Plot the IRA-QC LDPC base matrix H_b used in ldpc_decoder.v.

  ─ Code parameters: N=1024, K=512, M=512, rate=1/2
  ─ Base matrix M_b × N_b = 8 × 16
  ─ Lifting factor Z = 64
  ─ Each cell stores a cyclic-shift value 0..Z-1 (6'd63 = "no edge" sentinel)
  ─ Left 8 columns: parity part (dual-diagonal + identity, IRA-QC style)
  ─ Right 8 columns: systematic part (random shifts 0..31)

Reproduces simulation/ldpc_base_matrix.png from the actual RTL data
(ldpc_decoder.v lines 25-51).
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap, BoundaryNorm

# -----------------------------------------------------------
# Base matrix H_b — copied verbatim from ldpc_decoder.v
# 6'd63 means "no edge" (empty cell), valid shifts are 0..31
# -----------------------------------------------------------
NULL = -1                                # render as "·" / dark grey
H_b = np.array([
    # row 0 — cols 0..7 (parity)         cols 8..15 (systematic)
    [ 0,  0,NULL,NULL,NULL,NULL,NULL,NULL,   22, 17, 30,  3,  1, 12,  9,  0],
    # row 1
    [NULL, 0,  0,NULL,NULL,NULL,NULL,NULL,    5, 28, 15, 11, 20,  6, 25,  7],
    # row 2
    [NULL,NULL, 0,  0,NULL,NULL,NULL,NULL,   18,  2, 13, 27,  8, 23,  4, 16],
    # row 3
    [NULL,NULL,NULL, 0,  0,NULL,NULL,NULL,   10, 31, 21, 14, 29,  0, 19, 24],
    # row 4
    [NULL,NULL,NULL,NULL, 0,  0,NULL,NULL,   26,  7,  3, 18, 11, 14, 31,  2],
    # row 5
    [NULL,NULL,NULL,NULL,NULL, 0,  0,NULL,   13, 24,  9,  5, 29, 16,  8, 21],
    # row 6
    [NULL,NULL,NULL,NULL,NULL,NULL, 0,  0,   19, 12,  6, 27,  4, 30, 17, 15],
    # row 7
    [NULL,NULL,NULL,NULL,NULL,NULL,NULL, 0,  28, 20, 25, 10, 23,  1, 16,  3],
], dtype=int)

M_b, N_b = H_b.shape
Z = 64
N = N_b * Z          # 1024
K = (N_b - M_b) * Z  # 512

print(f"H_b shape: {H_b.shape}, Z={Z}, N={N}, K={K}")
print(f"valid shifts  : {(H_b != NULL).sum()} / {H_b.size} cells")
print(f"empty cells   : {(H_b == NULL).sum()}  (left half is sparse parity)")

# -----------------------------------------------------------
# Plot
# -----------------------------------------------------------
fig, ax = plt.subplots(figsize=(13, 6.5))

# Color map: empty → dark grey;  shift value → viridis 0..63
cmap = plt.cm.viridis.copy()
cmap.set_under("#3a3a3a")     # color for NULL

vmin, vmax = 0, 31
im = ax.imshow(np.where(H_b == NULL, vmin - 1, H_b),
               cmap=cmap, vmin=vmin, vmax=vmax,
               aspect="auto", interpolation="nearest")

# Annotate each cell
for i in range(M_b):
    for j in range(N_b):
        v = H_b[i, j]
        if v == NULL:
            ax.text(j, i, "·", ha="center", va="center",
                    fontsize=14, color="#aaaaaa")
        else:
            color = "white" if v < 16 else "black"
            ax.text(j, i, f"{v}", ha="center", va="center",
                    fontsize=11, color=color, weight="bold")

# Vertical separator: parity | systematic
ax.axvline(7.5, color="#e76f51", linewidth=2.5)
# Group headers above the matrix (use ax-fraction coords via .text on figure)
fig.text(0.30, 0.91, "Parity part  (8 cols, dual-diagonal IRA-QC)",
         ha="center", fontsize=11, color="#264653", weight="bold")
fig.text(0.72, 0.91, "Systematic part  (8 cols, random shifts 0..31)",
         ha="center", fontsize=11, color="#264653", weight="bold")

# Axes labels
ax.set_xticks(range(N_b))
ax.set_xticklabels([f"c{j}\n{j*Z}" for j in range(N_b)], fontsize=9)
ax.set_yticks(range(M_b))
ax.set_yticklabels([f"r{i}\n{i*Z}" for i in range(M_b)], fontsize=9)
ax.set_xlabel("Base column index   ( column j → bit indices [j·Z, (j+1)·Z) )",
              fontsize=11)
ax.set_ylabel("Base row index   ( row i → check indices [i·Z, (i+1)·Z) )",
              fontsize=11)

# Title + caption
fig.suptitle(
    "IRA-QC LDPC Base Matrix  H_b  (8 × 16, lifting factor Z = 64)\n"
    f"Code: N = {N}, K = {K}, rate = 1/2, dual-diagonal IRA-QC parity",
    fontsize=13, weight="bold", y=0.98,
)

# Colorbar
cbar = plt.colorbar(im, ax=ax, fraction=0.025, pad=0.02)
cbar.set_label("Cyclic shift value (0 .. Z-1)", fontsize=10)
cbar.set_ticks([0, 8, 16, 24, 31])

# Footer note
fig.text(0.5, 0.02,
         "·  =  empty cell (6'd63 sentinel in RTL = 'no edge' in Tanner graph)   "
         "·   number = cyclic shift of Z×Z circulant identity matrix",
         ha="center", fontsize=9, style="italic", color="#555")

plt.tight_layout(rect=[0, 0.04, 1, 0.88])

OUT = "/home/ysara/fpga_hdl/simulation/ldpc_base_matrix.png"
plt.savefig(OUT, dpi=120, bbox_inches="tight")
print(f"Saved {OUT}")
