#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Run by tools/run-test.sh after the machine has stopped, with the image
# closed and before the FAT checker: the swap file, read by mtools. On
# the 128K machine the shell's page was lent — to mapper in the script
# and again at the login shell — so /m6.swp is there, hidden, 16384
# bytes, written twice over the same clusters; on the 4 MB machine the
# kernel always had a segment to give, and nothing was ever lent.
set -eu
img=$M6_IMAGE
le32() { od -An -tu4 -j "$2" -N 4 "$1" | tr -d ' \n'; }
byte() { od -An -tu1 -j "$2" -N 1 "$1" | tr -d ' \n'; }
off=0
if [ "$(byte "$img" 510)" = 85 ] && [ "$(byte "$img" 450)" != 0 ]; then
    off=$(( $(le32 "$img" 454) * 512 ))
fi
list=$(MTOOLS_SKIP_CHECK=1 mdir -a -i "$img@@$off" ::)
case $img in
*m6-msx2-128k*)
    printf '%s\n' "$list" | grep -E -i -q '^m6 +swp +16 ?384 ' ||
        { echo "check: /m6.swp is not on the volume, 16384 bytes:" >&2; printf '%s\n' "$list" >&2; exit 1; }
    MTOOLS_SKIP_CHECK=1 mattrib -i "$img@@$off" ::/m6.swp | grep -q 'H' ||
        { echo "check: /m6.swp is not hidden" >&2; exit 1; }
    echo "  check: /m6.swp, 16384 bytes, hidden"
    ;;
*)
    if printf '%s\n' "$list" | grep -E -i -q '^m6 +swp '; then
        echo "check: /m6.swp was written on a machine with segments to spare:" >&2
        printf '%s\n' "$list" >&2
        exit 1
    fi
    echo "  check: no /m6.swp"
    ;;
esac
