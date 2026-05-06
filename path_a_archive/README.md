# Path A — ADI HDL Pluto port to LDSDR clg400 (incomplete)

## Goal
Port ADI plutosdr reference design (xc7z010clg225) to LDSDR 7010 rev2.1
(xc7z010clg400-2 + LVDS_25 AD9363) so we can integrate ofdm_ldpc_top
and run pass_flag=1 over real RF.

## Status: bitstream builds, but board doesn't boot Linux

### What works
- pluto_ldsdr Vivado project on build server (ADI HDL main + IGNORE_VERSION_CHECK)
- ADI library IPs built: axi_ad9361, axi_dmac, axi_tdd, util_pack, util_fir_*
- Synthesis + impl + bitstream generation OK (WNS=-0.086 ns, marginal)
- pluto_ldsdr.bit: 961488 bytes, IDCODE 0x03722093 (xc7z010 ✓)
- BOOT.bin packaged via bootgen with extracted FSBL/u-boot
  - PHT structure matches ORIG byte-for-byte (after manual patches at
    0x34 src_len, 0x40 fsbl_len, 0x48 checksum)
  - Bitstream correctly byte-swapped at 0x19770
  - u-boot at 0x1042c0 byte-identical to extracted

### What doesn't work
Board powers on but produces ZERO bytes on UART, no USB CDC enumeration.
FSBL likely halts before U-Boot hand-off.

### Root cause hypothesis
LDSDR is based on **plutosdr-fw v0.38** (per dev manual).  Its u-boot's
`adi_hwref` command reads custom hardware identification from PL via AXI.
Our ADI standard `axi_ad9361` BD lacks plutosdr-fw's hardware fingerprint
block (likely axi_sysid or specific GPIO).  When fingerprint mismatches,
u-boot silently switches stdout to nulldev and falls into DFU mode.

### Files
- `pluto_ldsdr/` — Vivado project source
- `pluto_ldsdr.bit` — 961KB compiled bitstream
- `BOOT_PATHA_FIX5.bin` — packaged BOOT.bin (failed boot)
- `fsbl_extracted.bin` — FSBL extracted from LDSDR original BOOT.bin
- `uboot_extracted.bin` — u-boot extracted from LDSDR original BOOT.bin

### Next path: plutosdr-fw v0.38 full-stack
Estimated 6-12 hours. Use plutosdr-fw build framework:
```bash
git clone https://github.com/analogdevicesinc/plutosdr-fw -b v0.38
cd plutosdr-fw && git submodule update --init --recursive
# Patch hdl/projects/pluto/ for clg400 + LVDS_25
make BOARD=pluto
```
This produces complete BOOT.bin with proper hardware fingerprint.
