# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the SD driver test on the Turbo cartridge: the
# same ROM, block and cards as m6sd, in the SD Mapper cartridge that
# presents the m6 block device and a 432K mapper of its own, so the
# kernel runs the driver in Turbo and every step's sectors go through
# the device's commands. m6sd.tcl's checks and probe apply; this one
# requires besides that the block's step 8 found Turbo in force.
set ::probe_rom_lst m6sd.lst
source [file join [file dirname [info script]] .. m6sd m6sd.tcl]
rename post_verdict post_verdict_m6sd
proc post_verdict {} {
    set seen 0
    if {![catch {get_screen} s]} {
        foreach r [split $s \n] { if {[string match "*turbo: yes*" $r]} { set seen 1 } }
    }
    if {!$seen} { return "the block did not report turbo: yes" }
    puts stderr "harness: $::test: the driver ran in Turbo"
    return [post_verdict_m6sd]
}
