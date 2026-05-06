#!/usr/bin/env python3
"""
Path X v2 — Software OFDM TX/RX over LDSDR's AD9363.

Cleaner version: skip manual DDS disable (kernel handles it auto when DMA
buffer is cyclic), use larger samples count (DMA alignment), explicit channel
setup.
"""
import iio
import numpy as np
import time
import sys

URI = "ip:192.168.2.1"

N_FFT, N_CP, N_DATA = 64, 16, 48
PILOT_A = 5793
PILOTS = {7, 21, 43, 57}
NULLS = {0} | set(range(27, 38))
DATA_BINS = sorted(set(range(64)) - PILOTS - NULLS)
TEST_BITS_LO = 0x0F0F0F0F


def build_symbol(bits64):
    freq = np.zeros(N_FFT, dtype=complex)
    bp = 0
    for b in DATA_BINS:
        if bp >= 64: break
        i_bit = (bits64 >> bp) & 1; bp += 1
        q_bit = (bits64 >> bp) & 1 if bp < 64 else 0; bp += 1
        freq[b] = complex(-PILOT_A if i_bit else PILOT_A,
                          -PILOT_A if q_bit else PILOT_A)
    for p in PILOTS:
        freq[p] = complex(PILOT_A, 0)
    t = np.fft.ifft(freq) * N_FFT
    return np.concatenate([t[-N_CP:], t])


def main():
    ctx = iio.Context(URI)
    print(f"[INFO] connected {URI}")

    phy = ctx.find_device("ad9361-phy")
    txdev = ctx.find_device("cf-ad9361-dds-core-lpc")
    rxdev = ctx.find_device("cf-ad9361-lpc")

    # SAFETY: TX_ATTEN -75 dB (≈ -69 dBm out, well below RX +2 dBm damage)
    for ch in (0, 1):
        phy.find_channel(f"voltage{ch}", True).attrs["hardwaregain"].value = "-75"
    print("[SAFETY] TX_ATTEN = -75 dB")

    # LO 2.4 GHz, sample 2.5 MHz
    phy.find_channel("altvoltage0", True).attrs["frequency"].value = "2400000000"
    phy.find_channel("altvoltage1", True).attrs["frequency"].value = "2400000000"
    phy.find_channel("voltage0", True).attrs["sampling_frequency"].value = "2500000"
    print("[CFG] LO=2.4GHz fs=2.5MHz")

    # RX manual gain 40 dB
    rx_in = phy.find_channel("voltage0", False)
    rx_in.attrs["gain_control_mode"].value = "manual"
    rx_in.attrs["hardwaregain"].value = "40"

    # Build TX: 64 OFDM symbols (5120 samples) — DMA-friendly aligned
    sym0 = build_symbol(TEST_BITS_LO)
    N_SYM = 64
    tx_iq = np.tile(sym0, N_SYM)
    scale = 28000.0 / np.max(np.abs(np.concatenate([tx_iq.real, tx_iq.imag])))
    tx_i = (tx_iq.real * scale).astype(np.int16)
    tx_q = (tx_iq.imag * scale).astype(np.int16)
    pack = np.empty(2 * len(tx_iq), dtype=np.int16)
    pack[0::2] = tx_i; pack[1::2] = tx_q
    print(f"[TX] {len(tx_iq)} IQ, peak |I|={np.max(np.abs(tx_i))} |Q|={np.max(np.abs(tx_q))}")

    # Enable TX channels (voltage0 = I0, voltage1 = Q0)
    tx_v0 = txdev.find_channel("voltage0", True)
    tx_v1 = txdev.find_channel("voltage1", True)
    tx_v0.enabled = True
    tx_v1.enabled = True

    # cyclic buffer (kernel auto-switches DAC source from DDS → DMA)
    tx_buf = iio.Buffer(txdev, len(tx_iq), True)
    tx_buf.write(bytearray(pack.tobytes()))
    tx_buf.push()
    print(f"[TX] cyclic buffer pushed")
    time.sleep(0.3)  # let TX path settle

    # RX
    rx_v0 = rxdev.find_channel("voltage0", False)
    rx_v1 = rxdev.find_channel("voltage1", False)
    rx_v0.enabled = True
    rx_v1.enabled = True
    rx_buf = iio.Buffer(rxdev, 8192, False)
    rx_buf.refill()
    rx_raw = rx_buf.read()
    rx = np.frombuffer(rx_raw, dtype=np.int16)
    rx_i = rx[0::2].astype(np.float32); rx_q = rx[1::2].astype(np.float32)
    rx_iq = rx_i + 1j * rx_q
    rms = np.sqrt(np.mean(np.abs(rx_iq)**2))
    print(f"[RX] {len(rx_iq)} samples RMS={rms:.1f} peak={np.max(np.abs(rx_iq)):.1f}")

    if rms < 10:
        print("[ERROR] RX too quiet — TX path silent")
        del tx_buf; del rx_buf
        return

    # CP autocorrelation sync
    L = len(rx_iq)
    M = min(L - N_FFT - N_CP, 2000)
    corr = np.zeros(M)
    for k in range(M):
        corr[k] = np.abs(np.sum(np.conj(rx_iq[k:k+N_CP]) * rx_iq[k+N_FFT:k+N_FFT+N_CP]))
    sync = int(np.argmax(corr))
    print(f"[SYNC] CP peak @ {sync} (max={corr[sync]:.1f})")

    # Demap symbol
    sym_start = sync + N_CP
    rx_freq = np.fft.fft(rx_iq[sym_start:sym_start+N_FFT]) / N_FFT
    decoded = 0; bi = 0
    for b in DATA_BINS:
        if bi >= 64: break
        s = rx_freq[b]
        decoded |= (1 if s.real < 0 else 0) << bi; bi += 1
        if bi >= 64: break
        decoded |= (1 if s.imag < 0 else 0) << bi; bi += 1

    expected = TEST_BITS_LO
    diff = (decoded & 0xFFFFFFFF) ^ expected
    pop = bin(diff).count("1")
    print(f"[DEMAP] decoded[63:0]=0x{decoded:016x} expect[31:0]=0x{expected:08x} mismatch={pop}/32")
    if pop == 0:
        print("[PASS] sym 0 first 32 bits perfectly recovered over RF")
    elif pop < 8:
        print(f"[NEAR] {pop} bits off — RF noise / sync drift")
    else:
        print(f"[FAIL] {pop}/32 wrong")

    del tx_buf; del rx_buf


if __name__ == "__main__":
    try: main()
    except Exception as e: print(f"[FATAL] {e}", file=sys.stderr); raise
