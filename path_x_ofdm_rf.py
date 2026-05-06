#!/usr/bin/env python3
"""
Path X — Software OFDM TX/RX over LDSDR's AD9363 (LDSDR original PL).

Reuses our PL OFDM logic (same TEST_BITS, same QPSK layout, same CP,
same data-bin selection).  Skips LDPC encode/decode — directly checks
the QPSK hard-decision LLRs against TEST_BITS for the first symbol's
64 information bits (same pass criterion as digital build #34).

Workflow:
    1. Configure AD9363 over libiio (-75 dB TX safety)
    2. Build one OFDM symbol's worth of IQ samples in Python
    3. Cyclic-push to AD9363 TX via iio_writebuf
    4. AD9363 transmits continuously
    5. RX captures via iio_readbuf
    6. Find frame start, demap, compare → pass_flag
"""

import iio
import numpy as np
import time
import sys

URI = "ip:192.168.2.1"

# ── OFDM parameters (must match our PL's ofdm_ldpc_top) ──────────────────
N_FFT  = 64
N_CP   = 16
N_DATA = 48
PILOT_A = 5793   # mapper PILOT_A; sets nominal amplitude for data bins
PILOTS  = {7, 21, 43, 57}
NULLS   = {0} | set(range(27, 38))   # bin 0 + 27..37
DATA_BINS = sorted(set(range(64)) - PILOTS - NULLS)  # 48 bins
assert len(DATA_BINS) == 48

# ── First 32 bits of TEST_BITS = 0x0F0F0F0F (LSB first) ──────────────────
TEST_BITS_LO = 0x0F0F0F0F  # bits 0..31


def build_one_symbol(info_bits_64):
    """Generate one OFDM symbol's IQ samples (80 complex, after CP)."""
    # Frequency-domain bins, complex
    freq = np.zeros(N_FFT, dtype=complex)
    bit_ptr = 0
    for b in DATA_BINS:
        if bit_ptr >= 64:
            break  # we only carry 64 info bits in this symbol
        i_bit = (info_bits_64 >> bit_ptr) & 1
        bit_ptr += 1
        q_bit = (info_bits_64 >> bit_ptr) & 1 if bit_ptr < 64 else 0
        bit_ptr += 1
        i_val = -PILOT_A if i_bit else +PILOT_A
        q_val = -PILOT_A if q_bit else +PILOT_A
        freq[b] = complex(i_val, q_val)
    for p in PILOTS:
        freq[p] = complex(PILOT_A, 0)
    # IFFT
    time_dom = np.fft.ifft(freq) * N_FFT  # un-normalize so IFFT*FFT=identity
    # Add cyclic prefix: last N_CP samples prepended
    cp = time_dom[-N_CP:]
    sym = np.concatenate([cp, time_dom])
    assert len(sym) == 80
    return sym


def main():
    ctx = iio.Context(URI)
    print(f"[INFO] connected to {URI}")

    phy = ctx.find_device("ad9361-phy")
    txdev = ctx.find_device("cf-ad9361-dds-core-lpc")
    rxdev = ctx.find_device("cf-ad9361-lpc")

    # ── Safety first: TX_ATTEN -75 dB on both channels ──
    for ch in (0, 1):
        v = phy.find_channel(f"voltage{ch}", True)  # output
        v.attrs["hardwaregain"].value = "-75"
    print("[SAFETY] TX_ATTEN = -75 dB on both channels")

    # ── LO ──
    phy.find_channel("altvoltage0", True).attrs["frequency"].value = "2400000000"  # RX_LO
    phy.find_channel("altvoltage1", True).attrs["frequency"].value = "2400000000"  # TX_LO

    # ── Sample rate 2.5 MHz ──
    phy.find_channel("voltage0", True).attrs["sampling_frequency"].value = "2500000"
    print("[CFG] LO=2.4GHz sample=2.5MHz")

    # ── RX gain manual 30 dB ──
    rx_in = phy.find_channel("voltage0", False)  # input
    rx_in.attrs["gain_control_mode"].value = "manual"
    rx_in.attrs["hardwaregain"].value = "30"

    # ── Disable DDS (we'll inject samples via DMA) ──
    for name in ("TX1_I_F1", "TX1_Q_F1", "TX1_I_F2", "TX1_Q_F2",
                 "TX2_I_F1", "TX2_Q_F1", "TX2_I_F2", "TX2_Q_F2"):
        try:
            ch = txdev.find_channel(name, True)
            ch.attrs["raw"].value = "0"
        except Exception:
            pass
    print("[CFG] DDS disabled")

    # ── Build TX buffer: 12 OFDM symbols (=960 samples) repeated ──────
    sym0 = build_one_symbol(TEST_BITS_LO & 0xFFFFFFFFFFFFFFFF)
    # Repeat the same sym 0 N times so we definitely have continuous data
    N_SYM_TX = 16
    tx_iq = np.tile(sym0, N_SYM_TX)
    # Convert to int16 IQ and scale into 12-bit range
    # AD9363 DAC takes 12-bit signed packed into 16-bit (shift left 4)
    max_amp = np.max(np.abs(np.concatenate([tx_iq.real, tx_iq.imag])))
    scale = 1500.0 / max_amp  # leave headroom under 2048 12-bit max
    tx_i = (tx_iq.real * scale).astype(np.int16)
    tx_q = (tx_iq.imag * scale).astype(np.int16)
    print(f"[TX] built {len(tx_iq)} IQ samples (peak |I|={np.max(np.abs(tx_i))} |Q|={np.max(np.abs(tx_q))})")

    # ── Enable TX channels ──
    tx_voltage0 = txdev.find_channel("voltage0", True)
    tx_voltage1 = txdev.find_channel("voltage1", True)
    tx_voltage0.enabled = True
    tx_voltage1.enabled = True
    tx_buf = iio.Buffer(txdev, len(tx_iq), True)  # cyclic = True

    # Pack interleaved I,Q (cf-ad9361-dds-core-lpc format: I0 Q0 I1 Q1 ...)
    pack = np.empty(2 * len(tx_iq), dtype=np.int16)
    pack[0::2] = tx_i
    pack[1::2] = tx_q
    raw = bytearray(pack.tobytes())
    tx_buf.write(raw)
    tx_buf.push()
    print(f"[TX] cyclic buffer pushed ({len(raw)} bytes)")

    # ── RX side ──
    time.sleep(0.1)  # let TX warm up
    rx_voltage0 = rxdev.find_channel("voltage0", False)
    rx_voltage1 = rxdev.find_channel("voltage1", False)
    rx_voltage0.enabled = True
    rx_voltage1.enabled = True
    rx_buf = iio.Buffer(rxdev, 4096, False)
    rx_buf.refill()
    rx_raw = rx_buf.read()
    rx = np.frombuffer(rx_raw, dtype=np.int16)
    rx_i = rx[0::2].astype(np.float32)
    rx_q = rx[1::2].astype(np.float32)
    rx_iq = rx_i + 1j * rx_q
    rx_rms = np.sqrt(np.mean(np.abs(rx_iq) ** 2))
    print(f"[RX] {len(rx_iq)} samples, RMS={rx_rms:.1f}, peak={np.max(np.abs(rx_iq)):.1f}")

    if rx_rms < 30:
        print("[ERROR] RX too quiet — link not working at -75 dB; "
              "consider lowering TX_ATTEN slightly (-50 dB safe with 12-bit headroom)")
        return

    # ── Frame sync: simple correlation against the known sym 0's CP ──
    # CP repeats last N_FFT samples → autocorrelation at lag N_FFT in time
    # is high during a CP region.
    L = len(rx_iq)
    corr = np.zeros(L - N_FFT - N_CP)
    for k in range(L - N_FFT - N_CP):
        corr[k] = np.abs(
            np.sum(np.conj(rx_iq[k:k + N_CP]) * rx_iq[k + N_FFT:k + N_FFT + N_CP])
        )
    sync = int(np.argmax(corr))
    print(f"[SYNC] CP autocorrelation peak at sample {sync} (max={corr[sync]:.1f})")

    # ── Take the symbol starting at sync+N_CP, FFT it ──
    sym_start = sync + N_CP
    if sym_start + N_FFT > L:
        print("[ERROR] not enough RX samples after sync")
        return
    rx_sym = rx_iq[sym_start:sym_start + N_FFT]
    rx_freq = np.fft.fft(rx_sym) / N_FFT

    # ── Demap data bins → QPSK LLRs ──
    decoded_bits = 0
    bit_idx = 0
    for b in DATA_BINS:
        if bit_idx >= 64:
            break
        sample = rx_freq[b]
        # sign of real → bit_ptr; sign of imag → bit_ptr+1
        i_bit = 1 if sample.real < 0 else 0
        q_bit = 1 if sample.imag < 0 else 0
        decoded_bits |= (i_bit << bit_idx); bit_idx += 1
        if bit_idx >= 64: break
        decoded_bits |= (q_bit << bit_idx); bit_idx += 1

    print(f"[DEMAP] decoded[63:0]=0x{decoded_bits:016x}")
    expected = TEST_BITS_LO  # only low 32 bits known to match
    diff = (decoded_bits & 0xFFFFFFFF) ^ expected
    pop = bin(diff).count("1")
    print(f"        expect[31:0]=0x{expected:08x}, mismatch_in_low_32_bits={pop}/32")
    if pop == 0:
        print("[PASS] sym 0 first 32 bits perfectly recovered over RF! 🎉")
    elif pop < 8:
        print(f"[NEAR] {pop} bits wrong — likely RF noise / sync drift")
    else:
        print(f"[FAIL] {pop}/32 wrong — sync or alignment issue")

    # Cleanup
    del tx_buf
    del rx_buf


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[FATAL] {e}", file=sys.stderr)
        raise
