# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test that boots from the SD Mapper
# kernel ROM in the cartridge that presents the m6 block device and a
# 432K memory mapper of its own: on m6-msx2-128k the BIOS has put page 3
# in that mapper already; on m6-msx2-128k-ram1 it has not, and the ROM's
# boot moves it there. Either way the kernel must find the cartridge's
# mapper as the primary, list the machine's own as not used, and run
# the driver in Turbo: the volume's row ends with the word. One card,
# slot 2 empty, /etc/rc through the shell. The verdict is those rows,
# the row that says device 2 has no volumes, the script's last line, the
# boot line with its tick count (a hint, printed), and the file the
# script wrote, read from the image with the emulator gone.
set show_screen 1
# Which mapper is which, by the machine: the cartridge's in subslot 3 of
# slot 1 on m6-msx2-128k and of slot 2 on -ram1, whose own mapper is in
# plain slot 1 — so a BIOS that changed its choice shows as a failure.
if {[machine_info config_name] eq "m6-msx2-128k-ram1"} {
    set cart {2\.3}; set own 1
} else {
    set cart {1\.3}; set own {3\.2}
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
proc has_text {want} {
    foreach r [rows] { if {[string first $want $r] >= 0} { return 1 } }
    return 0
}
proc has_re {re} {
    foreach r [rows] { if {[regexp $re $r]} { return 1 } }
    return 0
}

proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        puts stderr "boot3-turbo.tcl: rc done at [format %.2f [machine_info time]] s"
        foreach want [list \
            "^mapper $::cart: 27 segments, primary, " \
            "^mapper $::own: 8 segments, not used\$" \
            {^/mnt/a  enMSX 0\.1 SDHC .* / turbo$} \
            {^  2: no volumes$} \
        ] {
            if {![has_re $want]} {
                finish 1 "no row matching \"$want\" on the screen"
                return
            }
        }
        set n ""
        foreach r [rows] { if {[regexp {^boot: (\d+) ticks$} $r -> n]} break }
        if {$n eq ""} {
            finish 1 "no 'boot: N ticks' line on the screen"
            return
        }
        puts stderr "harness: $::test: boot: $n ticks since power-on, from the SD Mapper kernel ROM in Turbo (a hint)"
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
    if {$got ne "turbo\n"} { return "boot3 holds \"[string map {\n \\n} $got]\", not \"turbo\\n\"" }
    puts stderr "harness: $::test: boot3 holds what the script wrote"
    return ""
}
