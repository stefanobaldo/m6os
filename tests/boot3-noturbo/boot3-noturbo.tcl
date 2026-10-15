# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test on a cartridge that lies: its
# block device offers Turbo and names a subslot for its mapper, and no
# mapper answers there. The kernel ROM's boot must find that out and go
# on in Standard: the machine's own mapper stays the primary, the
# volume's row carries no Turbo word, and /etc/rc runs through the
# shell. On both machines the BIOS left page 3 in the machine's mapper,
# since the cartridge has none.
set show_screen 1
# The machine's own mapper, by the machine: 3.2 on m6-msx2-128k, plain
# slot 1 on -ram1.
if {[machine_info config_name] eq "m6-msx2-128k-ram1"} { set own 1 } else { set own {3\.2} }

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
        puts stderr "boot3-noturbo.tcl: rc done at [format %.2f [machine_info time]] s"
        if {![has_re "^mapper $::own: 8 segments, primary, "]} {
            finish 1 "the machine's mapper is not the primary"
            return
        }
        if {[has_re {27 segments}]} {
            finish 1 "a 27-segment mapper is listed: the liar's claim was believed"
            return
        }
        if {![has_re {^/mnt/a  enMSX 0\.1 SDHC .* /$}]} {
            finish 1 "no volume row without the Turbo word"
            return
        }
        if {[has_re { turbo$}]} {
            finish 1 "a row ends in turbo"
            return
        }
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_rc
}
after time 0.5 wait_rc
