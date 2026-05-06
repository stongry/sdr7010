#!/usr/bin/env python3
"""
Path X v3 — fine-tune sync timing + RX gain for 0-bit-error.
"""
import iio
import numpy as np
import time

URI = "ip:192.168.2.1"
N_FFT, N_CP = 64, 16
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
        freq[b] = complex(-PILOT_A if i_bit else PILOT_A, -PILOT_A if q_bit else PILOT_A)
    for p in PILOTS:
        freq[p] = complex(PILOT_A, 0)
    t = np.fft.ifft(freq) * N_FFT
    return np.concatenate([t[-N_CP:], t])


def demap_at(rx_iq, sym_start):
    rx_freq = np.fft.fft(rx_iq[sym_start:sym_start+N_FFT]) / N_FFT
    decoded = 0; bi = 0
    for b in DATA_BINS:
        if bi >= 64: break
        s = rx_freq[b]
        decoded |= (1 if s.real < 0 else 0) << bi; bi += 1
        if bi >= 64: break
        decoded |= (1 if s.imag < 0 else 0) << bi; bi += 1
    return decoded


def main():
    ctx = iio.Context(URI)
    phy = ctx.find_device("ad9361-phy")
    txdev = ctx.find_device("cf-ad9361-dds-core-lpc")
    rxdev = ctx.find_device("cf-ad9361-lpc")

    for ch in (0, 1):
        phy.find_channel(f"voltage{ch}", True).attrs["hardwaregain"].value = "-75"
    phy.find_channel("altvoltage0", True).attrs["frequency"].value = "2400000000"
    phy.find_channel("altvoltage1", True).attrs["frequency"].value = "2400000000"
    phy.find_channel("voltage0", True).attrs["sampling_frequency"].value = "2500000"
    rx_in = phy.find_channel("voltage0", False)
    rx_in.attrs["gain_control_mode"].value = "manual"

    sym0 = build_symbol(TEST_BITS_LO)
    N_SYM = 64
    tx_iq = np.tile(sym0, N_SYM)
    scale = 28000.0 / np.max(np.abs(np.concatenate([tx_iq.real, tx_iq.imag])))
    tx_i = (tx_iq.real * scale).astype(np.int16)
    tx_q = (tx_iq.imag * scale).astype(np.int16)
    pack = np.empty(2 * len(tx_iq), dtype=np.int16)
    pack[0::2] = tx_i; pack[1::2] = tx_q

    txdev.find_channel("voltage0", True).enabled = True
    txdev.find_channel("voltage1", True).enabled = True
    tx_buf = iio.Buffer(txdev, len(tx_iq), True)
    tx_buf.write(bytearray(pack.tobytes())); tx_buf.push()
    time.sleep(0.3)

    rxdev.find_channel("voltage0", False).enabled = True
    rxdev.find_channel("voltage1", False).enabled = True

    expected = TEST_BITS_LO
    print(f"{'rxgain':>7} {'rms':>6} {'sync':>5} {'sym_off':>7} {'mismatch':>8} {'decoded':>17}")
    best = (32, 0, 0, 0, 0, 0)
    for rxgain in (20, 30, 40, 50):
        rx_in.attrs["hardwaregain"].value = str(rxgain)
        time.sleep(0.1)
        rb = iio.Buffer(rxdev, 16384, False); rb.refill()
        d = np.frombuffer(rb.read(), dtype=np.int16).astype(np.float32)
        rx_iq = d[0::2] + 1j*d[1::2]
        rms = np.sqrt(np.mean(np.abs(rx_iq)**2))
        # Find best CP sync
        L = len(rx_iq)
        M = min(L - N_FFT - N_CP, 4000)
        corr = np.zeros(M)
        for k in range(M):
            corr[k] = np.abs(np.sum(np.conj(rx_iq[k:k+N_CP]) * rx_iq[k+N_FFT:k+N_FFT+N_CP]))
        sync = int(np.argmax(corr))
        # Try sym_off in -3..+3
        for off in range(-3, 4):
            sym_start = sync + N_CP + off
            if sym_start < 0 or sym_start + N_FFT > L: continue
            decoded = demap_at(rx_iq, sym_start)
            mismatch = bin((decoded & 0xFFFFFFFF) ^ expected).count("1")
            if mismatch < best[0]:
                best = (mismatch, rxgain, rms, sync, off, decoded)
            print(f"{rxgain:>7} {rms:>6.1f} {sync:>5} {off:>+7} {mismatch:>8} 0x{decoded&0xFFFFFFFF:08x}")
        del rb
    del tx_buf
    print()
    mismatch, rxgain, rms, sync, off, decoded = best
    print(f"BEST: rxgain={rxgain} rms={rms:.1f} sync={sync} off={off:+} mismatch={mismatch}/32")
    if mismatch == 0:
        print("[PASS] 0-bit-error OFDM RF demodulation 🎉")
    elif mismatch <= 2:
        print(f"[NEAR-PASS] {mismatch} bit error — likely noise floor")


if __name__ == "__main__":
    main()
