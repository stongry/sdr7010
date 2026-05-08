#!/usr/bin/env python3
"""
Plot the fixed-amplitude QPSK constellation used in tx_subcarrier_map.v
and qpsk_demod.v.

  ─ Power-normalized QPSK: each symbol has unit average power |s|² = 1
  ─ Fixed-point Q1.14 representation (16-bit signed)
  ─ Constellation point amplitude  A = 1/√2 × 2^13 = 5793  (matches RTL constant)
  ─ Pilot symbols: BPSK on real axis (±5793, 0) — same magnitude as data
  ─ Gray coding: adjacent points differ by 1 bit (so 1-symbol error → 1-bit error)

Reproduces simulation/qpsk_constellation.png.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# -----------------------------------------------------------
# Constellation parameters — match RTL exactly
# -----------------------------------------------------------
A = 5793           # = round(1/sqrt(2) * 2^13)
                   # exact: 1/sqrt(2) * 8192 ≈ 5792.62 → rounded to 5793

# Gray-coded mapping: bit pair (b1, b0) → complex point
# Convention from tx_subcarrier_map.v / qpsk_mod.v:
#   b1 b0 → (I, Q)
#   0  0  → (+A, +A)
#   0  1  → (+A, -A)
#   1  0  → (-A, +A)
#   1  1  → (-A, -A)
mapping = {
    "00": ( A,  A),
    "01": ( A, -A),
    "10": (-A,  A),
    "11": (-A, -A),
}

# Pilot symbols (BPSK on I axis, same magnitude as data)
pilots = [( A, 0), (-A, 0)]

# -----------------------------------------------------------
# Plot
# -----------------------------------------------------------
fig, ax = plt.subplots(figsize=(9, 9))

# Unit-power circle (the geometric meaning of "power-normalized")
theta = np.linspace(0, 2*np.pi, 360)
R = np.sqrt(A**2 + A**2)            # = A * sqrt(2) ≈ 8192 = 2^13
ax.plot(R*np.cos(theta), R*np.sin(theta),
        color="#aaaaaa", linewidth=1, linestyle="--", alpha=0.7,
        label=f"Unit-power circle  R = √2·A = {R:.0f} ≈ 2¹³")

# Axes
ax.axhline(0, color="black", linewidth=0.6)
ax.axvline(0, color="black", linewidth=0.6)

# QPSK data points
COLOR = {
    "00": "#e76f51",
    "01": "#e9c46a",
    "10": "#2a9d8f",
    "11": "#264653",
}
for bits, (i_v, q_v) in mapping.items():
    ax.scatter(i_v, q_v, s=550, color=COLOR[bits],
               edgecolors="black", linewidths=2, zorder=4,
               label=f"{bits} → ({i_v:+d}, {q_v:+d})")
    # bit-pair label
    ax.annotate(bits, xy=(i_v, q_v),
                xytext=(i_v + 600 * (1 if i_v > 0 else -1),
                        q_v + 600 * (1 if q_v > 0 else -1)),
                fontsize=18, weight="bold", ha="center",
                color=COLOR[bits])
    # numeric coords
    ax.annotate(f"({i_v:+5d}, {q_v:+5d})",
                xy=(i_v, q_v),
                xytext=(i_v, q_v - 1100 * (1 if q_v < 0 else -1)),
                fontsize=10, ha="center",
                color="#555")

# Pilot points
for (i_v, q_v) in pilots:
    ax.scatter(i_v, q_v, s=300, marker="s",
               color="white", edgecolors="#9b5de5", linewidths=2.5,
               zorder=3,
               label=f"pilot ({i_v:+d}, {q_v:+d})" if (i_v, q_v) == pilots[0] else None)

# Decision regions (light shading)
for x0, x1, y0, y1, c in [
    (0, 9000, 0, 9000, "#e76f51"),
    (0, 9000, -9000, 0, "#e9c46a"),
    (-9000, 0, 0, 9000, "#2a9d8f"),
    (-9000, 0, -9000, 0, "#264653"),
]:
    ax.fill_between([x0, x1], y0, y1, alpha=0.04, color=c)

# Annotate quadrants
ax.text(4500, 4500, "Q1\n(b1 b0 = 00)", ha="center", va="center",
        fontsize=10, alpha=0.5, style="italic")
ax.text(4500, -4500, "Q4\n(b1 b0 = 01)", ha="center", va="center",
        fontsize=10, alpha=0.5, style="italic")
ax.text(-4500, 4500, "Q2\n(b1 b0 = 10)", ha="center", va="center",
        fontsize=10, alpha=0.5, style="italic")
ax.text(-4500, -4500, "Q3\n(b1 b0 = 11)", ha="center", va="center",
        fontsize=10, alpha=0.5, style="italic")

# axes range and ticks
ax.set_xlim(-9500, 9500); ax.set_ylim(-9500, 9500)
ax.set_xlabel("In-phase component  I  (16-bit signed Q1.14)", fontsize=11)
ax.set_ylabel("Quadrature component  Q  (16-bit signed Q1.14)", fontsize=11)
ax.set_xticks([-A, 0, A])
ax.set_xticklabels([f"-A=-{A}", "0", f"+A={A}"])
ax.set_yticks([-A, 0, A])
ax.set_yticklabels([f"-A=-{A}", "0", f"+A={A}"])

ax.set_title("Fixed-amplitude QPSK constellation  —  tx_subcarrier_map / qpsk_demod\n"
             f"A = 1/√2 × 2¹³ = {A}  (Q1.14 fixed-point, power-normalized)",
             fontsize=13, weight="bold", pad=15)

ax.set_aspect("equal")
ax.grid(True, linestyle=":", alpha=0.5)

# Legend
ax.legend(loc="lower left", fontsize=8, framealpha=0.9)

# Footer math note
fig.text(0.5, 0.01,
         "Power normalization:  E[|s|²] = A² + A² = 2A² = 2·(1/√2)²·2²⁶ = 2²⁶  →  "
         "scaled unit power 1.0 (in Q1.14 reference)   ·   "
         "Gray code: adjacent symbols differ by 1 bit",
         ha="center", fontsize=9, style="italic", color="#555")

plt.tight_layout(rect=[0, 0.03, 1, 1])

OUT = "/home/ysara/fpga_hdl/simulation/qpsk_constellation.png"
plt.savefig(OUT, dpi=120, bbox_inches="tight")
print(f"Saved {OUT}")
