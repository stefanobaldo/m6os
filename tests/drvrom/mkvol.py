#!/usr/bin/env python3
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The pattern test driver's volume: a 64-sector FAT12 superfloppy — one
# reserved sector, one FAT of one sector, a root of 16 entries in one
# sector, one sector per cluster — holding READER, the program the test
# spawns, and PATTERN.BIN, whose data the driver generates rather than
# stores. Writes the image's first sectors, up to where PATTERN.BIN
# begins, as <out> (the driver's bank carries them); the layout comes
# from tests/drvrom/layout.inc, which the driver, the test and the reader
# assemble with, so that the four agree by construction. The image is
# written by the same rules the kernel's enumeration applies, so that
# what the driver serves is a volume m6 mounts.
#
#   mkvol.py <out> <reader image>
import os, re, struct, sys

out = sys.argv[1]
reader = open(sys.argv[2], "rb").read()
layout = {}
here = os.path.dirname(os.path.abspath(__file__))
for m in re.finditer(r"^(PT_\w+)\s+equ\s+([0-9+A-Z_]+)", open(os.path.join(here, "layout.inc")).read(), re.M):
    layout[m.group(1)] = eval(m.group(2), {}, dict(layout))
SECTORS, RSVD, NFATS, SPF, NROOT = layout["PT_SECTORS"], 1, 1, 1, 16
readersecs, patsecs = layout["PT_RSECS"], layout["PT_PATSECS"]
rootsec = RSVD + NFATS * SPF
datasec = rootsec + NROOT * 32 // 512
clusters = SECTORS - datasec
assert len(reader) <= readersecs * 512, f"READER is {len(reader)} bytes, more than PT_RSECS sectors"
assert readersecs + patsecs <= clusters, (readersecs, patsecs, clusters)

# The boot sector: a BPB the kernel's bi_bpb accepts, no code.
boot = bytearray(512)
boot[0:3] = b"\xEB\xFE\x90"
boot[3:11] = b"M6DRVROM"
struct.pack_into("<HBHBHHBHHHII", boot, 11, 512, 1, RSVD, NFATS, NROOT, SECTORS, 0xF8, SPF, 1, 1, 0, 0)
boot[36:38] = b"\x00\x00"
boot[38] = 0x29
struct.pack_into("<I", boot, 39, 0x6D360001)
boot[43:54] = b"PATTERN VOL"
boot[54:62] = b"FAT12   "
boot[510:512] = b"\x55\xAA"

# The FAT: clusters 2.. in two chains, READER's then PATTERN.BIN's.
fat = bytearray(512)
def setent(c, v):
    o = c * 3 // 2
    if c & 1:
        fat[o] = (fat[o] & 0x0F) | ((v << 4) & 0xF0); fat[o + 1] = (v >> 4) & 0xFF
    else:
        fat[o] = v & 0xFF; fat[o + 1] = (fat[o + 1] & 0xF0) | ((v >> 8) & 0x0F)
setent(0, 0xFF8); setent(1, 0xFFF)
def chain(first, n):
    for i in range(n):
        setent(first + i, first + i + 1 if i < n - 1 else 0xFFF)
rfirst = 2
pfirst = rfirst + readersecs
chain(rfirst, readersecs)
chain(pfirst, patsecs)

# The root: two entries, no dates.
root = bytearray(512)
def entry(i, name, first, size):
    e = bytearray(32)
    e[0:11] = name
    e[11] = 0x20
    struct.pack_into("<H", e, 26, first)
    struct.pack_into("<I", e, 28, size)
    root[i * 32:(i + 1) * 32] = e
entry(0, b"READER     ", rfirst, len(reader))
entry(1, b"PATTERN BIN", pfirst, patsecs * 512)

k = datasec + (pfirst - 2)
assert k == layout["PT_K"], (k, layout["PT_K"])
img = bytes(boot) + bytes(fat) + bytes(root) + reader + b"\0" * (readersecs * 512 - len(reader))
assert len(img) == k * 512, (len(img), k)
with open(out, "wb") as f:
    f.write(img)
print(f"mkvol: {out}: {k} sectors carried, PATTERN.BIN at {k}, {patsecs} sectors")
