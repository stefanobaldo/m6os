# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Files the legacy test needs that are too large or too regular to
# commit: dos/big.com, a 30K program that ends at its first instruction
# (jp 0), the launch line's load; and the end of /etc/rc — sixty launches
# of it between two ticks, then rc done — appended to the committed part,
# because a nested script's shell would cost the segment the program needs.
set staging $::env(M6_STAGING)
file mkdir [file join $staging dos]
set fh [open [file join $staging dos big.com] wb]
puts -nonewline $fh [binary format ccc 0xC3 0 0][string repeat [binary format c 0] 30717]
close $fh
# The end of /etc/rc: the launches, then the line the harness waits for.
set fh [open [file join $staging etc rc] ab]
puts -nonewline $fh "/t/tick\n[string repeat "dos /dos/big.com\n" 58]/t/tick\necho rc done\n"
close $fh
