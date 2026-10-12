# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The file rd64 reads, written by tools/mkdisk.tcl before it imports the
# staging directory: big, 65 536 bytes, byte i = (i ^ (i >> 8)) & 0xFF.
set fh [open [file join $::env(M6_STAGING) big] wb]
set bytes {}
for {set i 0} {$i < 65536} {incr i} {
    lappend bytes [expr {($i ^ ($i >> 8)) & 0xFF}]
}
puts -nonewline $fh [binary format c* $bytes]
close $fh
