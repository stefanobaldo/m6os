# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Files the product test needs that are too large or too regular to
# commit, written by tools/mkdisk.tcl before it imports the staging
# directory: big, 65 536 bytes, what cp copies while gap measures;
# etc/bench1, sixty one-sector commands of which the first and the last
# print the kernel's tick; etc/bench2, sixty three-stage pipelines of
# which the first and the last end in a stamp.
# Only two lines of each reach the screen, so the measurement holds no
# file write and no scrolling. rows, what more pages to show that it
# counts rows as the console does: nine lines of 100 columns, one of 80,
# ten TABs and x, then a and b — 23 rows up to a, so the stop falls
# before b.
set staging $::env(M6_STAGING)
set fh [open [file join $staging big] wb]
puts -nonewline $fh [string repeat [binary format c 0x5A] 65536]
close $fh
file mkdir [file join $staging etc]
set fh [open [file join $staging etc bench1] wb]
puts -nonewline $fh "/t/tick\n[string repeat "true\n" 58]/t/tick\n"
close $fh
set fh [open [file join $staging etc bench2] wb]
puts -nonewline $fh "echo x | cat | /t/stamp\n[string repeat "echo x | cat | /t/drain\n" 58]echo x | cat | /t/stamp\n"
close $fh
set fh [open [file join $staging rows] wb]
puts -nonewline $fh "[string repeat "[string repeat w 100]\n" 9][string repeat v 80]\n[string repeat \t 10]x\na\nb\n"
close $fh
