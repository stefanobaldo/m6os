# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the legacy file test. The machine boots M6.COM
# and the kernel runs /etc/rc through the shell: eight raw .COM programs
# under /dosf, each printing "<name> ok" through the BIOS, or the step
# that failed. When the script's last line shows, the rows are read and
# the verdict given; the images are then judged by the host's FAT checker
# (the fsck marker), with the emulator gone.
set show_screen 1
set problems {}

proc problem {what} {
    lappend ::problems $what
    puts stderr "dosf.tcl: $what"
}
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
proc expect_screen {want msg} { if {![has_row $want]} { problem $msg } }

proc wait_rc {} {
    if {[has_row "rc done"]} {
        puts stderr "dosf.tcl: rc done at [format %.2f [machine_info time]] s"
        check_rc
        return
    }
    if {[machine_info time] > 400} {
        problem "rc did not finish"
        check_rc
        return
    }
    after time 0.5 wait_rc
}
after time 1 wait_rc

proc check_rc {} {
    expect_screen "rc start" "rc start not on the screen"
    foreach p {hfile hfind hdir henv hproc hparse hmisc hslot copy64} {
        if {![has_row "$p ok"]} {
            set line ""
            foreach r [rows] { if {[string match "$p fail*" $r]} { set line $r } }
            problem [expr {$line eq "" ? "$p printed neither ok nor fail" : $line}]
        }
    }
    expect_screen "hmisc via write" "handle 1 did not reach the screen"
    expect_screen "con handle" "a handle opened on CON did not reach the screen"
    # copy64's launch between the two tick stamps: the disk work of 64 KB
    # written, 64 KB copied and 64 KB read back, since the kernel's clock
    # runs inside its calls and stands still while the program computes.
    set stamps {}
    foreach r [rows] { if {[string is integer -strict $r]} { lappend stamps $r } }
    if {[llength $stamps] == 2} {
        set ticks [expr {[lindex $stamps 1] - [lindex $stamps 0]}]
        puts stderr [format "harness: %s: copy64 — 64 KB written, copied and read back through handles: %d ticks, %.2f s (an emulator's figure: a hint)" \
            $::test $ticks [expr {$ticks / 60.0}]]
    } else {
        problem "[llength $stamps] tick stamps on the screen, not 2"
    }
    if {[llength $::problems]} {
        finish 1 "FAIL: [join $::problems {; }]"
    } else {
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
    }
}
