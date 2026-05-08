#!/usr/bin/env python3
"""Convert Vivado .bit (with header) to raw .bin for Linux fpga_manager.

Vivado .bit has a small ASCII header (design name / part / date / time)
followed by 0xff padding then 0xaa995566 sync word + bitstream payload.
fpga_manager (with file=...) wants the byte-swapped .bin starting with
the sync word. We strip the header and byte-swap each 32-bit word.
"""
import sys, struct

src = sys.argv[1]
dst = sys.argv[2]

with open(src, "rb") as f:
    data = f.read()

# Find sync word 0xAA995566 (or byte-swapped 0x66559AA)
sync_be = b'\xaa\x99\x55\x66'  # big-endian as in .bit
idx = data.find(sync_be)
if idx < 0:
    sync_le = b'\x66\x55\x99\xaa'
    idx = data.find(sync_le)
print(f"sync word at offset 0x{idx:x}, payload {len(data)-idx} bytes")

payload = data[idx:]

# Byte-swap every 4 bytes (Linux fpga_manager wants little-endian)
swapped = bytearray()
for i in range(0, len(payload), 4):
    chunk = payload[i:i+4]
    if len(chunk) == 4:
        swapped += chunk[::-1]
    else:
        swapped += chunk

with open(dst, "wb") as f:
    f.write(swapped)

print(f"Wrote {dst} ({len(swapped)} bytes)")
