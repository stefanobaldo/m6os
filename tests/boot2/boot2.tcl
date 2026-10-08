# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test that boots through NEXTOR.SYS:
# the Nextor kernel ROM loads the m6 loader in place of Nextor's own
# system file, with nothing else of Nextor's on the disk, and the kernel
# runs /etc/rc through the shell. When the script's last line shows, the
# login shell is up; the verdict is that line, the boot line with its
# tick count (a hint, printed), and the file the script wrote, read from
# the image with the emulator gone. The product has no mailbox.
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

proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        puts stderr "boot2.tcl: rc done at [format %.2f [machine_info time]] s"
        set n ""
        foreach r [rows] { if {[regexp {^boot: (\d+) ticks$} $r -> n]} break }
        if {$n eq ""} {
            finish 1 "no 'boot: N ticks' line on the screen"
            return
        }
        puts stderr "harness: $::test: boot: $n ticks since power-on, through NEXTOR.SYS (a hint)"
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.2 wait_rc
}
after time 0.5 wait_rc

# The file the script wrote, read from the image.
proc post_verdict {} {
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda $dir} err]} { return "export of / failed: $err" }
    set path ""
    foreach f [glob -nocomplain -directory $dir -tails *] {
        if {[string tolower $f] eq "boot2"} { set path [file join $dir $f] }
    }
    if {$path eq ""} { return "/boot2 was not written" }
    set fh [open $path rb]
    set got [read $fh]
    close $fh
    if {$got ne "nextor\n"} { return "/boot2 holds \"[string map {\n \\n} $got]\", not \"nextor\\n\"" }
    puts stderr "harness: $::test: /boot2 holds what the script wrote"
    return ""
}
