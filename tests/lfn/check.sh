#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Run by tools/run-test.sh after the machine has stopped, with the image
# closed and before the FAT checker: the bytes patch.tcl changed are put
# back, from <image>.patch, so the checker judges what the kernel wrote
# and not the cases planted for the reader.
set -eu
img=$M6_IMAGE
[ -f "$img.patch" ] || { echo "check: $img.patch missing" >&2; exit 1; }
while read -r off old; do
    printf "$(printf '\\%03o' "$old")" | dd of="$img" bs=1 seek="$off" count=1 conv=notrunc 2> /dev/null
done < "$img.patch"
echo "  check: the planted long-name cases put back"

# The names the kernel wrote on the second volume, read back by mtools:
# the first logical partition of the extended chain, entry 2 of the MBR.
le32() { od -An -tu4 -j "$2" -N 4 "$1" | tr -d ' \n'; }
ext=$(le32 "$img" 470)
vol=$(( (ext + $(le32 "$img" $((ext * 512 + 446 + 8)))) * 512 ))
list=$(MTOOLS_SKIP_CHECK=1 mdir -i "$img@@$vol" ::)
sub=$(MTOOLS_SKIP_CHECK=1 mdir -i "$img@@$vol" "::/RENAME~1")
want() {
    printf '%s\n' "$1" | grep -F -q -- "$2" ||
        { echo "check: mtools does not list \"$2\":" >&2; printf '%s\n' "$1" >&2; exit 1; }
}
want "$list" "hw       txt"
want "$list" "Read Me First.md"
want "$list" "MIXED    txt"
want "$list" "SPACER~9 ROM"
want "$list" "spacer 9.rom"
want "$list" "RENAME~1     <DIR>"
want "$list" "Renamed Long Dir"
want "$sub" "crossing a sector.txt"
want "$sub" "crossing a cluster.txt"
want "$sub" "x.y.z moved"
gone() {
    printf '%s\n' "$1" | grep -F -q -- "$2" &&
        { echo "check: mtools still lists \"$2\":" >&2; printf '%s\n' "$1" >&2; exit 1; }
    return 0
}
gone "$list" "Hello World.txt"
gone "$list" "HELLOW~1"
gone "$list" "spacer 3.rom"
gone "$list" "SPACER~4"
gone "$list" "Empty Long Dir"
# hw.txt: a short entry in lower case with no long name beside it.
printf '%s\n' "$list" | grep -E '^hw       txt ' | grep -q -v 'hw.txt' ||
    { echo "check: hw.txt is not a lower-case short entry alone:" >&2; printf '%s\n' "$list" >&2; exit 1; }
echo "  check: mtools reads the names written back"
