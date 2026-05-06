# Phase 0 — RF Physical Link Verification (Achieved)

LDSDR original BOOT.bin is restored (BOOT_ORIG_BACKUP.bin).
Device tree patched to enable ad9361 driver chain.

## DT patch applied

```sh
# Decompile dtb
dtc -I dtb -O dts /mnt/sdcard/devicetree.dtb -o devicetree.dts

# Change status of three nodes from "disabled" to "okay":
#   /amba/spi@e0006000/ad9361-phy@0
#   /fpga-axi@0/cf-ad9361-lpc@79020000
#   /fpga-axi@0/cf-ad9361-dds-core-lpc@79024000

# Recompile
dtc -I dts -O dtb devicetree.dts -o devicetree_new.dtb
```

## iio devices that became visible after patch

```
iio:device0: ad9361-phy           # SPI configuration
iio:device1: xadc                 # Zynq monitoring
iio:device2: cf-ad9361-dds-core-lpc # TX (DDS or DMA buffer)
iio:device3: cf-ad9361-lpc        # RX (DMA buffer)
```

## Safe RF config (do this on every boot)

```sh
# SAFETY FIRST — TX attenuation must be set BEFORE enabling TX
iio_attr -u ip:192.168.2.1 -c -o ad9361-phy voltage0 hardwaregain "-75"
iio_attr -u ip:192.168.2.1 -c -o ad9361-phy voltage1 hardwaregain "-75"

# Verify
iio_attr -u ip:192.168.2.1 -c -o ad9361-phy voltage0 hardwaregain  # → -75.000000 dB
```

## Physical link verified

| TX_ATTEN | RX RMS |
|----------|--------|
| -75 dB | 23.7 (noise floor) |
| -30 dB | **284.5** (12× louder) |

DDS at 100 kHz tone, scale 0.25, sample rate 2.5 MHz, both LO at 2.4 GHz.

Conclusion: TX-RX SMA cable shorted, AD9363 transmits and receives at safe power.

## Next: Path Y — PL OFDM integration

Build a new PL bitstream containing:
- `ad9361_phy` IP (from LDSDR — already verified to work)
- `ofdm_ldpc_top` (our existing PoC, perfect on symbol 0)
- Async FIFO between ad9361_phy.data_clk (~80 MHz @ 40 MSPS) and FCLK0 (50 MHz)
- 16-bit ↔ 12-bit IQ conversion
- OPTIONAL: replace `xfft_stub` with Vivado xfft IP for true OFDM in the channel

PS side: keep using LDSDR's original Linux + ad9361-phy driver to configure AD9363 over SPI (TX_ATTEN/LO/sample-rate/RX-gain). Our PL OFDM runs autonomously after AD9363 emits LVDS data_clk.
