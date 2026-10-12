# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test that boots from the kernel ROM
# built for the FBLabs SD Mapper V2: m6 in the emulated cartridge in
# place of its Nextor kernel ROM, the cartridge's own SDXC driver bank
# taken into it and called through the adapter, two cards — an SDHC and
# a standard-capacity one addressed by byte — nothing of a system's on
# them, and the kernel runs /etc/rc through the shell. Every sector it
# took to get there went through the driver's SPI window, the card
# select and the timer of the emulated cartridge. The verdict is the
# driver's own lines (its banner, each card detected with its version),
# the listing's rows for both cards, the script's last line, the boot
# line with its tick count (a hint, printed), and the file the script
# wrote on each card, read from the images with the emulator gone.
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
            "FBLabs SDXC driver v1.1.0"
            "Card 1: SDV2"
            "Card 2: SDV1"
            "/mnt/a  FBLabs SDXC"
            "/mnt/b  FBLabs SDXC"
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
        puts stderr "harness: $::test: boot: $n ticks since power-on, from the SD Mapper kernel ROM through its Nextor driver (a hint)"
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_rc
}
after time 0.5 wait_rc

# The file the script wrote on each card, read from the images.
proc check_card {drive} {
    set dir $::env(M6_EXPORT).$drive
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export $drive $dir} err]} { return "export of $drive failed: $err" }
    set path ""
    foreach f [glob -nocomplain -directory $dir -tails *] {
        if {[string tolower $f] eq "boot3"} { set path [file join $dir $f] }
    }
    if {$path eq ""} { return "boot3 was not written on $drive" }
    set fh [open $path rb]
    set got [read $fh]
    close $fh
    if {$got ne "rom\n"} { return "boot3 on $drive holds \"[string map {\n \\n} $got]\", not \"rom\\n\"" }
    return ""
}
proc post_verdict {} {
    foreach drive {hda hdb} {
        set err [check_card $drive]
        if {$err ne ""} { return $err }
    }
    puts stderr "harness: $::test: boot3 holds what the script wrote on both cards"
    return ""
}
