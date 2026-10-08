# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the test that boots Nextor through the m6 loader:
# ESC is held from the first frame, so when the kernel ROM jumps to
# NEXTOR.SYS the loader loads Nextor's own system file, kept as
# MSXDOS2.SYS, over itself. The verdict needs two rows: the loader's
# line, which proves the path was the loader's and not the kernel's own
# fallback for a missing NEXTOR.SYS, and the marker Nextor's AUTOEXEC.BAT
# prints. The key is released once the loader has spoken, or at 8 s.
set show_screen 1
set seen_loader 0

keymatrixdown 7 0x04
after time 8 { keymatrixup 7 0x04 }

proc screen_text {} {
    if {[catch {get_screen} s]} { return "" }
    return $s
}
proc wait_nextor {} {
    set s [screen_text]
    if {!$::seen_loader && [string first "m6: loading Nextor" $s] >= 0} {
        set ::seen_loader 1
        keymatrixup 7 0x04
        puts stderr "boot2key.tcl: the loader is loading Nextor at [format %.2f [machine_info time]] s"
    }
    if {[string first "m6 chain ok" $s] >= 0} {
        if {!$::seen_loader} {
            finish 1 "Nextor came up without the loader's line: the kernel's own fallback, not NEXTOR.SYS"
            return
        }
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.2 wait_nextor
}
after time 0.5 wait_nextor
