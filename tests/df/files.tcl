# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The file /etc/rc copies onto the large volume: 65 536 bytes, 128
# clusters of one sector there.
if {[info exists ::env(M6_STAGING)] && [info exists ::env(M6_STEP)]} {
    set bytes {}
    for {set i 0} {$i < 65536} {incr i} { lappend bytes [expr {($i ^ ($i >> 8)) & 0xFF}] }
    set fh [open [file join $::env(M6_STAGING) big] wb]
    puts -nonewline $fh [binary format c* $bytes]
    close $fh
}
