# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the driver-contract test: the ROM carries the
# pattern block in its driver bank and the test in bank 2, and the
# kernel runs the test as process 0 the moment it has booted. What the
# harness adds is the keyboard: when the test says it has spawned the
# reader, ^C is pressed into one of the reader's driver calls, and the
# test waits for the reader to die of it. The report is the screen; the
# verdict is the mailbox, as for every test.
set show_screen 1
set pressed 0

proc rows {} {
    if {[catch {get_screen} s]} { return {} }
    set out {}
    foreach r [split $s \n] { lappend out [string trimright $r] }
    return $out
}
proc has_row {want} {
    foreach r [rows] { if {$r eq $want} { return 1 } }
    return 0
}
# CTRL and C, held long enough for a scan: the matrix rows of kbd_map.
proc press_ctrl_c {} {
    keymatrixdown 6 0x02
    after time 0.05 { keymatrixdown 3 0x01 }
    after time 0.12 { keymatrixup 3 0x01 }
    after time 0.17 { keymatrixup 6 0x02 }
}
proc watch {} {
    if {!$::pressed && [has_row "10 reader"]} {
        set ::pressed 1
        puts stderr "drvrom.tcl: the reader is up at [format %.2f [machine_info time]] s; ^C in 1 s"
        after time 1.0 press_ctrl_c
        return
    }
    after time 0.1 watch
}
after time 0.5 watch
