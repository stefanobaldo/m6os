# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the SD driver test on the cartridge whose block
# offers the FAT accelerator and not Turbo: the same ROM, block and
# cards as m6sd, every sector through the SPI window, and the two
# queries answered by the device. m6sd.tcl's checks and probe apply —
# its step 9 line must say the queries answered — and this one requires
# besides that the block's step 8 found Turbo not offered.
set ::probe_rom_lst m6sd.lst
source [file join [file dirname [info script]] .. m6sd m6sd.tcl]
rename post_verdict post_verdict_m6sd
proc post_verdict {} {
    set seen 0
    if {![catch {get_screen} s]} {
        foreach r [split $s \n] { if {[string match "*turbo: no*" $r]} { set seen 1 } }
    }
    if {!$seen} { return "the block did not report turbo: no" }
    puts stderr "harness: $::test: Turbo not offered, the driver in Standard"
    return [post_verdict_m6sd]
}
