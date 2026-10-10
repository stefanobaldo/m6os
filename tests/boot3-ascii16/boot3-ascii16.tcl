# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the test that boots the kernel ROM built from
# Nextor's standalone ASCII16 kernel, as a plain ASCII16 cartridge with
# nothing behind it. The ROM's bank switch is the SD Mapper's, so what
# this proves is the ROM's own path through that register: the INIT
# trampoline and the hook, the relocation, the mapper probe, both driver
# calls, the copies and the takeover, up to a kernel that enumerates no
# volume and says so — the bytes an SD Mapper ROM shares with this one.
# Nothing of a driver is proved here: the standalone driver has no
# hardware, and no sector is read. The verdict is the ROM's banner, the
# wall line with no work area taken, the mapper line, the boot line with
# its tick count (a hint, printed), and the kernel's init failure for a
# root that is not there.
set show_screen 1

proc rows {} {
    # get_screen throws while the VDP is in a graphical mode, which it is
    # while the machine boots.
    if {[catch {get_screen} s]} { return {} }
    set out {}
    foreach r [split $s \n] { lappend out [string trimright $r] }
    return $out
}
proc has_row {want} {
    foreach r [rows] { if {$r eq $want} { return 1 } }
    return 0
}
proc has_match {re} {
    foreach r [rows] { if {[regexp $re $r]} { return 1 } }
    return 0
}

proc wait_init {} {
    if {[has_row "init: /bin/sh: error 2"]} {
        puts stderr "boot3-ascii16.tcl: the kernel stopped for want of a root at [format %.2f [machine_info time]] s"
        foreach {what how} {
            {the ROM's banner} {has_match {^m6 }}
            {the wall line with no work area} {has_row "wall F380h, drivers 1"}
            {the mapper line} {has_match {^mapper .* segments}}
        } {
            if {![eval $how]} {
                finish 1 "$what is not on the screen"
                return
            }
        }
        set n ""
        foreach r [rows] { if {[regexp {^boot: (\d+) ticks$} $r -> n]} break }
        if {$n eq ""} {
            finish 1 "no 'boot: N ticks' line on the screen"
            return
        }
        puts stderr "harness: $::test: boot: $n ticks since power-on, from the ROM through an ASCII16 register (a hint)"
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_init
}
after time 0.5 wait_init
