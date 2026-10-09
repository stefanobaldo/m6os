#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# tools/check-rom.sh <m6 rom> <nextor rom>: the bytes the kernel ROM must
# reproduce from the Nextor kernel ROM it takes its driver from, compared
# with the driver bank's after every build. The driver bank is bank 7 of
# both files, and it calls into bank 0 at fixed addresses written by hand
# in src/rom/rom.asm; a byte wrong there shows only as a corrupt sector
# read, so the assembler's word is not taken for it.
#
#   1. 40DBh-40E1h of bank 0 equal the driver bank's: the part of CALBNK
#      that runs in the bank called.
#   2. 7FD0h-7FFFh of every bank equal the driver bank's: CHGBNK.
#   3. Every bank begins with AB; 40FEh of bank 0 is 7, the driver's bank;
#      bank 7 is the Nextor ROM's bank 7, whole.
#   4. The Nextor ROM's bank 7 says it is bank 7 (40FFh): an eight-bank
#      kernel ROM, not a loose driver.
#   5. The driver bank's INIT trampoline jumps to an address bank 0 serves
#      with a jump of its own: the BIOS may scan the cartridge with any
#      bank visible.
set -eu
rom=${1:?usage: tools/check-rom.sh <m6 rom> <nextor rom>}
nextor=${2:?usage: tools/check-rom.sh <m6 rom> <nextor rom>}
BANK=16384

size() { wc -c < "$1" | tr -d ' '; }
# slice <file> <offset> <length>: those bytes, on stdout.
slice() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null; }
# byte <file> <offset>: one byte, in decimal.
byte() { od -An -tu1 -j "$2" -N 1 "$1" | tr -d ' \n'; }
fail() { echo "check-rom: $*" >&2; exit 1; }

[ "$(size "$rom")" = $((8 * BANK)) ] || fail "$rom is not 128K"
[ "$(size "$nextor")" = $((8 * BANK)) ] || fail "$nextor is not 128K"
drv=$((7 * BANK))

# 4. The input first: a Sunrise kernel ROM has its driver in bank 7.
[ "$(byte "$nextor" $((drv + 0xFF)))" = 7 ] ||
    fail "$nextor: bank 7 does not say it is bank 7 at 40FFh; not an eight-bank kernel ROM"

# 1. CALBNK's bytes that run in the bank called.
slice "$rom" $((0xDB)) 7 > "$rom.a"
slice "$nextor" $((drv + 0xDB)) 7 > "$rom.b"
cmp -s "$rom.a" "$rom.b" || { rm -f "$rom.a" "$rom.b"; fail "bank 0's 40DBh-40E1h differ from the driver bank's CALBNK"; }

# 2. CHGBNK in every bank.
slice "$nextor" $((drv + 0x3FD0)) 48 > "$rom.b"
b=0
while [ "$b" -lt 8 ]; do
    slice "$rom" $((b * BANK + 0x3FD0)) 48 > "$rom.a"
    cmp -s "$rom.a" "$rom.b" || { rm -f "$rom.a" "$rom.b"; fail "bank $b's 7FD0h-7FFFh differ from the driver's CHGBNK"; }
    # 3. The header.
    [ "$(slice "$rom" $((b * BANK)) 2)" = "AB" ] || { rm -f "$rom.a" "$rom.b"; fail "bank $b does not begin with AB"; }
    b=$((b + 1))
done
rm -f "$rom.a" "$rom.b"
[ "$(byte "$rom" $((0xFE)))" = 7 ] || fail "bank 0's K_SIZE (40FEh) is not 7"
slice "$rom" $drv $BANK > "$rom.a"
slice "$nextor" $drv $BANK > "$rom.b"
cmp -s "$rom.a" "$rom.b" || { rm -f "$rom.a" "$rom.b"; fail "bank 7 is not the Nextor ROM's bank 7"; }
rm -f "$rom.a" "$rom.b"

# 5. The driver bank's INIT: xor a / call 7FD0h / jp <target> at 40F6h.
[ "$(byte "$nextor" $((drv + 0xF6)))" = 175 ] && [ "$(byte "$nextor" $((drv + 0xFA)))" = 195 ] ||
    fail "the driver bank's INIT at 40F6h is not the trampoline expected"
lo=$(byte "$nextor" $((drv + 0xFB)))
hi=$(byte "$nextor" $((drv + 0xFC)))
target=$((hi * 256 + lo))
[ "$target" -ge $((0x4000)) ] && [ "$target" -lt $((0x7FD0)) ] ||
    fail "the driver bank's INIT jumps to $(printf %04X "$target"), outside bank 0"
[ "$(byte "$rom" $((target - 0x4000)))" = 195 ] ||
    fail "bank 0 holds no jump at $(printf %04X "$target"), where the driver bank's INIT lands"

echo "check-rom: $rom reproduces the driver bank's CALBNK, CHGBNK and INIT target"
