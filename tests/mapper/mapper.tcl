# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause

set show_screen 1

# The boot time the kernel prints after its summary: a number of ticks on
# the screen, read here as a hint for the log, never compared against one.
# A screen row is padded to its width, hence the trailing spaces.
proc post_verdict {} {
    foreach r [split [get_screen] \n] {
        if {[regexp {^boot: (\d+) ticks *$} $r -> n]} {
            puts stderr "harness: $::test: boot: $n ticks since power-on (a hint)"
            return ""
        }
    }
    return "no 'boot: N ticks' line on the screen"
}
