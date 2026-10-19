# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the df test: /etc/rc copies a 64K file onto the
# second volume — the synthetic FAT16 whose table is 256 sectors — and
# runs df. The verdict is the script's last line; after it, df's row for
# that volume is read off the screen and checked against the image: its
# size from the boot sector's geometry, its free space from a count of
# the zero entries of the first table, made here with the emulator gone.
# On a cartridge whose block offers the FAT accelerator the count df
# printed is the device's; elsewhere the kernel's walk; the row must be
# the same either way.
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
proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
        return
    }
    after time 0.1 wait_rc
}
after time 0.5 wait_rc

proc le {data off n} {
    set v 0
    for {set i [expr {$n - 1}]} {$i >= 0} {incr i -1} {
        binary scan [string index $data [expr {$off + $i}]] cu b
        set v [expr {($v << 8) | $b}]
    }
    return $v
}
# The FAT16 volume of the slave image: size and free clusters.
proc volume_from_image {path} {
    set fh [open $path rb]
    set mbr [read $fh 512]
    set start [le $mbr 0x1C6 4]
    seek $fh [expr {$start * 512}]
    set bs [read $fh 512]
    set spc [le $bs 0x0D 1]
    set rsvd [le $bs 0x0E 2]
    set nfats [le $bs 0x10 1]
    set rootent [le $bs 0x11 2]
    set total [le $bs 0x13 2]
    if {$total == 0} { set total [le $bs 0x20 4] }
    set fatsz [le $bs 0x16 2]
    set rootsec [expr {$rootent * 32 / 512}]
    set data [expr {$rsvd + $nfats * $fatsz + $rootsec}]
    set nclus [expr {($total - $data) / $spc}]
    seek $fh [expr {($start + $rsvd) * 512}]
    set fat [read $fh [expr {$fatsz * 512}]]
    close $fh
    set free 0
    for {set c 2} {$c <= $nclus + 1} {incr c} {
        if {[le $fat [expr {$c * 2}] 2] == 0} { incr free }
    }
    return [list [expr {$nclus * $spc / 2}] [expr {$free * $spc / 2}]]
}
proc post_verdict {} {
    lassign [volume_from_image $::env(M6_SLAVE_IMAGE)] size free
    set used [expr {$size - $free}]
    set row ""
    foreach r [rows] {
        if {[regexp {^/mnt/b +(\d+) +(\d+) +(\d+) FAT16$} $r -> gs gu gf]} { set row $r }
    }
    if {$row eq ""} { return "no df row for /mnt/b on the screen" }
    # The header over the columns: each of Size, Used and Free ends where
    # the row's number below it ends, and Type starts with the filesystem.
    set head ""
    foreach r [rows] { if {[string match "Volume *" $r]} { set head $r } }
    if {$head eq ""} { return "no df header on the screen" }
    set ends {}
    foreach {s e} [concat {*}[lrange [regexp -all -inline -indices {\S+} $row] 1 end]] { lappend ends $e }
    set i 0
    foreach w {Size Used Free} {
        set e [expr {[string first $w $head] + [string length $w] - 1}]
        if {$e != [lindex $ends $i]} { return "df's header: $w ends at column $e, the row's number at [lindex $ends $i]" }
        incr i
    }
    if {[string first Type $head] != [string first FAT16 $row]} { return "df's header: Type is not over the filesystem" }
    if {$gs != $size || $gu != $used || $gf != $free} {
        return "df printed $gs $gu $gf for /mnt/b; the image says $size $used $free"
    }
    set a 0
    foreach r [rows] { if {[regexp {^/mnt/a +\d+ +\d+ +\d+ FAT12$} $r]} { set a 1 } }
    if {!$a} { return "no df row for /mnt/a on the screen" }
    puts stderr "harness: $::test: /mnt/b: $size KB, $used used, $free free, as the image says"
    return ""
}
