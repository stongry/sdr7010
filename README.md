# sdr7010 — OFDM + LDPC Digital Loopback on Zynq-7010 (LDSDR rev2.1)

End-to-end OFDM + LDPC physical-layer experiment running on a **LDSDR 7010 rev2.1** board (Zynq xc7z010clg400-2). The current state validates **full PL data flow in digital loopback** — TX path, RX path, LDPC decoder all execute, with `rx_done=1` confirmed via EMIO GPIO read from PS u-boot. `pass_flag=0` because the LDPC HB matrix is currently inconsistent for `Z=64`; that is the next item being fixed.

## What works today

Build #19 (`BOOT_NEW18.bin`) running on the board produces the following EMIO state right after PL bring-up:

| EMIO bit | Signal | Value | Meaning |
|---|---|---|---|
| [0] | `pass_flag` | 0 | `rx_decoded != TEST_BITS` (LDPC HB mismatch) |
| [1] | `rx_done` | **1** | LDPC decoder produced first `rx_valid_out` |
| [2] | `dbg_llr_done_seen` | **1** | `llr_buffer` filled 512 LLRs |
| [3] | `dbg_eq_seen` | **1** | `channel_est` produced equalised samples |
| [19:4] | `dbg_demod_cnt` | 554 | QPSK demod valids (close to expected 576 for N_SYM=12) |
| [31:20] | `dbg_ifft_cnt` | 940 | mapper output cycles (matches 12 sym × ~80 cycles) |

```
startup_gen ─▶ ldpc_encoder ─▶ tx_subcarrier_map ─▶ IFFT(stub) ─▶ cp_insert
                                                                        │
                                                              (PL-internal loopback)
                                                                        ▼
ldpc_decoder ◀─ llr_buffer ◀─ qpsk_demod ◀─ rx_demap ◀─ channel_est ◀─ FFT(stub) ◀─ cp_remove
```

## Bug-hunt diary (19 Vivado builds to reach `rx_done=1`)

| Build | Symptom | Root cause | Fix |
|---|---|---|---|
| #1–6 | (early PlutoSDR misroute, board recovery) | Discovered LDSDR is **not** PlutoSDR, restored original BOOT.bin | Switch to xc7z010clg400-2 part + LDSDR PS7 config |
| #7 | USERLED stayed dim from power-on (pull-up only, never driven) | `make_bd_pins_external` silently failed on already-connected pin | Use `create_bd_port -dir O led_heartbeat` + `connect_bd_net` |
| #8 | `peripheral_aresetn` stuck low → entire `ofdm_ldpc_top` held in reset | `proc_sys_reset_0/mb_debug_sys_rst` is **HIGH-active**, was tied to `xlconst_one` | New `xlconst_zero` to mb_debug_sys_rst |
| #9 | Heartbeat OK, POR OK, `tx_started=0` | WNS = -4.524 ns at 100 MHz (path needs 14.5 ns) | Drop FCLK0 to 50 MHz → WNS +1.7 ns |
| #10–11 | Bitstream identical run-to-run despite source changes | Synth optimised away unreachable RTL | Add `(* DONT_TOUCH = "TRUE" *)` on `ofdm_ldpc_top` instance + `(* KEEP *)` on `cp_insert` registers |
| #12 | `tx_started=1` but `tx_streaming=0` | (suspected `cp_insert` deadlock — turned out to be downstream issue, but kept the fix) | `cp_insert.rd_bank` reset value `1 → 0` so reader activates on bank A's first fill |
| #13 | `tx_streaming=1` but RX chain empty | Need RX path visibility | Add 6 latch + 32-bit EMIO debug taps |
| #14 | `dbg_enc_seen=0` — LDPC encoder never produced `valid_out` | `ldpc_encoder` instantiated with `Z=64` but internal `cycle_cnt` hard-coded `[4:0]` (max 31), so phase-1 jump-out condition `cycle_cnt == Z-1 = 63` was unreachable → infinite loop in phase 1 | Change `cycle_cnt`, `cyc`, `src_bit` to `[$clog2(Z)-1:0]` |
| #15–17 | `tx_streaming=1`, encoder/mapper OK, but `rx_done=0` | Successive RX-side debug taps narrowed gap to `demod_cnt < 512` (llr_buffer threshold) | Track demod count via 16-bit EMIO counter |
| #18 | `demod=508/528`, just shy of 512 threshold | Edge effects + ~one symbol of misalignment loss | Bump `N_SYM 11 → 12`, giving demod count of 554 (>512) |
| #19 | **`rx_done=1`, `llr_done=1`, `eq=1`** ✅ | (this is the current state) | full TX→RX dataflow confirmed; pass_flag still 0 due to LDPC HB matrix |

## Known stubs / why `pass_flag=0`

These are intentional simplifications used to bring the data path up first:

1. **`xfft_stub.v`** — combinational pass-through, *not* a real IFFT/FFT. The "frequency-domain" bins are just shifted samples.
2. **`channel_est.v` `STREAM_MODE=1`** — registered pass-through, no pilot-based estimation/equalisation.
3. **`ldpc_encoder.v` HB matrix** — shift values were authored for `Z=32` (max 31), but the design now runs `Z=64`. Encoder and decoder *both* use the same Hb, so they're internally consistent in *structure*, but the encoder's parity computation isn't a valid LDPC code, and the decoder's iterative BP can't converge to the original info bits.

The next milestone (in progress) is to make the LDPC HB matrix consistent end-to-end for `Z=64` so that in noiseless loopback, `rx_decoded == TEST_BITS` and `pass_flag=1`.

## Repo layout

```
.
├── ofdm_ldpc_pl.v          # Module-reference top for BD; POR + startup_gen + EMIO debug latches
├── ofdm_ldpc_top.v         # OFDM + LDPC datapath (TX→RX in one box)
├── ofdm_ldpc_rf_top.v      # RF wrapper (next phase, AD9363-facing)
├── ldpc_encoder.v          # QC-LDPC encoder
├── ldpc_decoder.v          # QC-LDPC layered min-sum decoder
├── tx_subcarrier_map.v     # Codeword bits → QPSK → IFFT input frame (pilot/null/data)
├── rx_subcarrier_demap.v   # Equaliser bins → data-bin only
├── qpsk_mod.v              # (unused — mapping is inline)
├── qpsk_demod.v            # Sign-based LLR (registered, 1-cycle latency)
├── cp_insert.v             # Ping-pong buffer + 16-sample CP prepend
├── cp_remove.v             # Frame-sync, CP strip
├── channel_est.v           # STREAM_MODE pass-through (full pilot/interp also implemented)
├── llr_buffer.v            # Distributed-RAM 512×8 even/odd, fires `valid_out` after 512 writes
├── llr_assembler.v         # (legacy)
├── xfft_stub.v             # Combinational identity pretending to be xfft_0
├── startup_gen.v           # 1000-cycle delay → 1-cycle pulse (auto-trigger TX)
├── ad9363_cmos_if.v        # PlutoSDR-style CMOS interface (NOT used on LDSDR LVDS)
├── run_ldsdr_digital.tcl   # Vivado batch script — build digital-loopback BOOT.bin's PL bitstream
├── run_rf_linux.tcl        # PlutoSDR RF build (legacy)
├── run_rf.tcl              # earlier RF variants
├── run_bd2.tcl             # earlier BD variant
├── run_sim.tcl             # sim helpers
├── ldsdr_ps7_config.tcl    # 618 PCW_* params extracted from LDSDR's design_1_bd.tcl (PS7 MIO/DDR/USB/I2C/SPI)
├── ldsdr_toppin.xdc        # LDSDR LVDS pin-map for AD9363 (next phase reference)
├── ldsdr_design_1_bd.tcl   # full LDSDR original BD (next phase reference)
├── ldsdr_ad9361_top_ref.v  # LDSDR original top (next phase reference)
├── ldsdr_ad9361_phy_ref/   # LDSDR ad9361_phy IP (LVDS+IDDR/ODDR+IDELAY) — drop-in for next phase
├── ldsdr_dds_dq_ref/       # LDSDR DDS test pattern IP (reference)
└── pluto*.xdc              # PlutoSDR pin-maps (legacy)
```

## How to build

On the build server (Vivado 2024.2, xc7z010clg400-2):

```bash
source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh
vivado -mode batch -source run_ldsdr_digital.tcl
# → produces /home/eea/ofdm_ldpc_ldsdr.bit
```

Then splice the bitstream into the original `BOOT.bin` (preserving the partition header table — FSBL won't load if PHT/checksums change), copy onto the SD card's BOOT partition, insert into the LDSDR board, and reset.

The PL EMIO can be sampled from u-boot **before** Linux boots:

```
Pluto> md.l 0xE000A068 1   # Bank-2 DATA_RO = EMIO[31:0] from xlconcat
```

The 32-bit value decodes per the bit-layout table above.

## Next milestones

1. **LDPC HB matrix fix** — make encoder + decoder a self-consistent QC-LDPC for `Z=64`, so noiseless loopback round-trips `TEST_BITS`. *(in progress)*
2. **Real FFT** — replace `xfft_stub` with Vivado xfft IP (`N=64`, IFFT+FFT pair).
3. **Channel estimator** — switch `channel_est.STREAM_MODE=0` once OFDM is real.
4. **RF loopback** — drop `ad9361_phy` from LDSDR's IP repo, add cross-clock-domain FIFOs (data_clk ~122 MHz ↔ FCLK0 50 MHz), program AD9363 via PS SPI0 (or boot original Linux + iio), TX1↔RX1 SMA loop with attenuation.

## Hardware

- LDSDR 7010 rev2.1 (Zynq xc7z010clg400-2, 512 MB DDR3, AD9363 RF transceiver, FT4232 USB UART, SD-card boot)
- Vivado 2024.2 on a remote build server
- u-boot's `Pluto>` prompt for EMIO read-back without Linux

## Acknowledgements

Bug hunt (especially Vivado's silent dead-code elimination and `mb_debug_sys_rst`'s polarity surprise) carried out interactively. The original LDSDR board files (PS7 config, AD9363 pinmap, ad9361_phy IP) were extracted from the manufacturer's `LDSDR(7010_rev2.1).rar` and are referenced under `ldsdr_*_ref*` for the upcoming RF phase.
