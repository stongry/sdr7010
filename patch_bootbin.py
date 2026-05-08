#!/usr/bin/env python3
"""Patch BFP BOOT.bin's image header so BootROM accepts it.

Failed BOOT.bin has source_length=0 and image_length=0 at offset 0x34/0x40
because bootgen used [bootloader, load=0x0, startup=0x0] with raw fsbl bin
and didn't fill the size fields. BootROM rejects the image silently.

Fix:
  0x34 = source_length = 0x18008  (fsbl_extracted.bin size = 98312)
  0x40 = image_length  = 0x18008
  0x48 = header checksum recomputed.

Zynq image header checksum (from UG585):
  Sum of 32-bit words from 0x20 to 0x46 (count = (0x48-0x20)/4 = 10 words),
  bitwise NOT, masked to 32 bits, stored at 0x48.
"""
import struct
import sys
import os

src = sys.argv[1]   # input .bin (BFP failed)
dst = sys.argv[2]   # output .bin (patched)

with open(src, "rb") as f:
    data = bytearray(f.read())

print(f"Input  : {src} ({len(data)} bytes)")

FSBL_SIZE = 0x18008  # path_a_archive/fsbl_extracted.bin

# 0x34 = source_length
struct.pack_into("<I", data, 0x34, FSBL_SIZE)
# 0x40 = image_length
struct.pack_into("<I", data, 0x40, FSBL_SIZE)

# Recompute header checksum: sum of words at 0x20, 0x24, ..., 0x44 (10 words),
# bitwise NOT, lower 32 bit.
total = 0
for off in range(0x20, 0x48, 4):
    w = struct.unpack_from("<I", data, off)[0]
    total = (total + w) & 0xFFFFFFFF
checksum = (~total) & 0xFFFFFFFF
struct.pack_into("<I", data, 0x48, checksum)

print(f"Patched 0x34 = source_length = 0x{FSBL_SIZE:08x}")
print(f"Patched 0x40 = image_length  = 0x{FSBL_SIZE:08x}")
print(f"Patched 0x48 = checksum      = 0x{checksum:08x}")

with open(dst, "wb") as f:
    f.write(data)

print(f"Output : {dst} ({len(data)} bytes)")
print()
print("Verify (xxd 0x20..0x4F):")
for off in range(0x20, 0x50, 16):
    line = " ".join(f"{b:02x}" for b in data[off:off+16])
    print(f"  {off:08x}: {line}")
