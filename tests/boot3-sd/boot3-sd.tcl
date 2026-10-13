# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test that boots from the kernel ROM
# built for the FBLabs SD Mapper V2 with m6's own SD driver: m6 in the
# emulated cartridge, one card in slot 1 — an SDHC card with nothing of
# a system's on it — and slot 2 empty, and the kernel runs /etc/rc
# through the shell. Every sector it took to get there went through the
# driver's SPI window and the card select of the emulated cartridge. The
# verdict is the listing's row for the card, named from its CID with
# its class, the row that says device 2 has no volumes, the script's last
# line, the boot line with its tick count (a hint, printed), and the
# file the script wrote, read from the image with the emulator gone.
set show_screen 1

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
proc has_text {want} {
    foreach r [rows] { if {[string first $want $r] >= 0} { return 1 } }
    return 0
}

proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        puts stderr "boot3-sd.tcl: rc done at [format %.2f [machine_info time]] s"
        foreach want {
            "/mnt/a  enMSX 0.1 SDHC"
            "  2: no volumes"
        } {
            if {![has_text $want]} {
                finish 1 "no row with \"$want\" on the screen"
                return
            }
        }
        set n ""
        foreach r [rows] { if {[regexp {^boot: (\d+) ticks$} $r -> n]} break }
        if {$n eq ""} {
            finish 1 "no 'boot: N ticks' line on the screen"
            return
        }
        puts stderr "harness: $::test: boot: $n ticks since power-on, from the SD Mapper kernel ROM through m6's own SD driver (a hint)"
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_rc
}
after time 0.5 wait_rc

# The file the script wrote, read from the image.
proc post_verdict {} {
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda $dir} err]} { return "export of the card failed: $err" }
    set path ""
    foreach f [glob -nocomplain -directory $dir -tails *] {
        if {[string tolower $f] eq "boot3"} { set path [file join $dir $f] }
    }
    if {$path eq ""} { return "boot3 was not written on the card" }
    set fh [open $path rb]
    set got [read $fh]
    close $fh
    if {$got ne "rom\n"} { return "boot3 holds \"[string map {\n \\n} $got]\", not \"rom\\n\"" }
    puts stderr "harness: $::test: boot3 holds what the script wrote"
    return ""
}
