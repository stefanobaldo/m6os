# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the kernel ROM's disk workload: m6 booted from
# the cartridge with its own driver, /etc/rc running the utilities over
# the files files.tcl wrote (cat, cat of two, sort | uniq, wc), and the
# login shell up when the script's last line shows. The verdict is that
# line, then the files the script wrote, exported from the image with
# the emulator gone and compared byte for byte with what the same
# generators give; run-test.sh runs the FAT checker on the image after.
set show_screen 1
source [file join [file dirname [info script]] files.tcl]

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
proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        puts stderr "romfs.tcl: rc done at [format %.2f [machine_info time]] s"
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_rc
}
after time 0.5 wait_rc

proc slurp {dir name} {
    set path ""
    foreach f [glob -nocomplain -directory $dir -tails *] {
        if {[string tolower $f] eq $name} { set path [file join $dir $f] }
    }
    if {$path eq ""} { return -code error "/$name was not written" }
    set fh [open $path rb]
    set got [read $fh]
    close $fh
    return $got
}
proc post_verdict {} {
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda $dir} err]} { return "export of / failed: $err" }
    set big [romfs_big]
    set want [dict create big2 $big big3 "$big$big" \
        u [join [lsort -unique [split [string trimright [romfs_text] \n] \n]] \n]\n]
    dict for {name bytes} $want {
        if {[catch {slurp $dir $name} got]} { return $got }
        if {$got ne $bytes} {
            return "/$name holds [string length $got] bytes that differ from the [string length $bytes] expected"
        }
    }
    if {[catch {slurp $dir n} got]} { return $got }
    if {![regexp {^\s*131072 big3\s*$} $got]} {
        return "/n holds \"[string map {\n \\n} $got]\", not wc's count of big3"
    }
    puts stderr "harness: $::test: big2, big3, u and n hold what the script's commands give"
    return ""
}
