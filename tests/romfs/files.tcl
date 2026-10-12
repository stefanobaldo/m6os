# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The files /etc/rc works on, written by tools/mkdisk.tcl before it
# imports the staging directory, and generated again by romfs.tcl for
# the comparison: big, 65 536 bytes, byte i = (i ^ (i >> 8)) & 0xFF;
# text, 400 lines "wNNN" with NNN = 37 i mod 101 — out of order, every
# value repeated.
proc romfs_big {} {
    set bytes {}
    for {set i 0} {$i < 65536} {incr i} {
        lappend bytes [expr {($i ^ ($i >> 8)) & 0xFF}]
    }
    return [binary format c* $bytes]
}
proc romfs_text {} {
    set out ""
    for {set i 0} {$i < 400} {incr i} {
        append out [format "w%03d\n" [expr {(37 * $i) % 101}]]
    }
    return $out
}
if {[info exists ::env(M6_STAGING)] && [info exists ::env(M6_STEP)]} {
    set fh [open [file join $::env(M6_STAGING) big] wb]
    puts -nonewline $fh [romfs_big]
    close $fh
    set fh [open [file join $::env(M6_STAGING) text] wb]
    puts -nonewline $fh [romfs_text]
    close $fh
}
