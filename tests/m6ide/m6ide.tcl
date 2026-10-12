# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the Sunrise IDE driver test: the ROM carries the
# driver in its bank 7 and the test in bank 2, and the kernel runs the
# test as process 0 the moment it has booted. The numbers are the
# evidence, so the screen stays in the log on a pass too. After the
# verdict, the slave's image is read with the emulator gone and its last
# 32 sectors compared with the pattern the test wrote through the driver
# (byte i of sector n is the low byte of 7 n + i, xor 55h in the
# sector's second half).
set show_screen 1
if {![info exists ::probe_strict]} { set ::probe_strict 1 }
if {![info exists ::probe_lst]} { set ::probe_lst build/kernel-noadapter.lst }
source [file join [file dirname [info script]] di.tcl]

proc post_verdict {} {
    set path $::env(M6_SLAVE_IMAGE)
    set fh [open $path rb]
    set size [file size $path]
    seek $fh [expr {$size - 32 * 512}]
    set got [read $fh]
    close $fh
    set first [expr {$size / 512 - 32}]
    for {set k 0} {$k < 32} {incr k} {
        set n [expr {$first + $k}]
        set d [expr {(7 * $n) & 0xFF}]
        for {set i 0} {$i < 512} {incr i} {
            set want [expr {($d + ($i & 0xFF)) & 0xFF}]
            if {$i >= 256} { set want [expr {$want ^ 0x55}] }
            binary scan [string index $got [expr {$k * 512 + $i}]] cu have
            if {$have != $want} {
                return "the slave's sector $n byte $i holds [format %02X $have], not [format %02X $want]"
            }
        }
    }
    puts stderr "harness: $::test: the slave's last 32 sectors hold the pattern"
    return [probe_report]
}
