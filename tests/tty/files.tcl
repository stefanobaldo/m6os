# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# A file the tty test reads, written by tools/mkdisk.tcl before it imports
# the staging directory: big.bin, 65 536 bytes, what rdf reads in a loop
# so that a ^C lands inside a long read.
set staging $::env(M6_STAGING)
set fh [open [file join $staging big.bin] wb]
puts -nonewline $fh [string repeat [binary format c 0x5A] 65536]
close $fh
