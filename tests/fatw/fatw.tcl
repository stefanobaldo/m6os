# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the fatw test. After the verdict: the stamp the
# created file got, against the host's clock; the writer's ticks, turned
# into KB/s for the log — a hint in the emulator, the gate's line on the
# bench; and the files the writer left, exported through the emulator's
# own FAT code and compared byte by byte with what they should hold. The
# two copies of every table and the checker's verdict are the run
# script's, once the emulator has closed the images.
set show_screen 1

# On the Turbo cartridge, a device that lies: the allocator's one
# next-free answer of the run (step 13's 257th cluster) is rewritten as
# the kernel receives it, to 1 — the reserved entry, which a chain must
# never take. The allocator must refuse it and find the cluster itself,
# so the files, the counts and the checker's verdict stay what an honest
# device gives. The address is the instruction after fat_alloc's call to
# fat_query, from the switched part's listing, its bytes checked so that
# the breakpoint acts only with that part mapped; ::lie_hl and ::lie_de
# hold the answer told.
set ::lies 0
if {![info exists ::lie_hl]} { set ::lie_hl 1 }
if {![info exists ::lie_de]} { set ::lie_de "" }
if {[info exists ::env(M6_CART)] && $::env(M6_CART) eq "turbo"} {
    set fh [open [file join $::env(M6_TEST_DIR) .. .. build kseg.lst] r]
    set state ""
    set ::lie_at ""
    foreach line [split [read $fh] \n] {
        if {![regexp {^\s*\d+\+*\s+([0-9A-F]{4})\s+(.*)$} $line -> a rest]} { continue }
        if {$state eq "call"} { set ::lie_at 0x$a; set ::lie_op 0x[string range $rest 0 1]; break }
        if {[string match "*.query:*" $rest]} { set state query }
        if {$state eq "query" && [string match "*call    fat_query*" $rest]} { set state call }
    }
    close $fh
    if {$::lie_at eq ""} { puts stderr "fatw.tcl: no call to fat_query after .query in kseg.lst"; exit 2 }
    proc lie {} {
        if {[peek $::lie_at] != $::lie_op || ([reg f] & 1)} { return }
        if {$::lies} { return }
        if {$::lie_hl ne ""} { reg hl $::lie_hl }
        if {$::lie_de ne ""} { reg de $::lie_de }
        incr ::lies
    }
    debug set_bp $::lie_at {} {lie}
}

proc days_from_civil {y m d} {
    if {$m <= 2} { incr y -1 }
    set era [expr {($y >= 0 ? $y : $y - 399) / 400}]
    set yoe [expr {$y - $era * 400}]
    set doy [expr {(153 * ($m + ($m > 2 ? -3 : 9)) + 2) / 5 + $d - 1}]
    set doe [expr {$yoe * 365 + $yoe / 4 - $yoe / 100 + $doy}]
    return [expr {$era * 146097 + $doe - 719468}]
}

# The pattern the writer lays down: byte i = (i ^ (i >> 8)) & 0xFF; with
# inverted set, bytes 30000..32999 inverted.
proc pattern {inverted} {
    set bytes {}
    for {set i 0} {$i < 65536} {incr i} {
        set b [expr {($i ^ ($i >> 8)) & 0xFF}]
        if {$inverted && $i >= 30000 && $i < 33000} { set b [expr {$b ^ 0xFF}] }
        lappend bytes $b
    }
    return [binary format c* $bytes]
}

proc post_verdict {} {
    set rows [split [get_screen] \n]
    # The stamp: FAT date and time words, against the host's local clock.
    set line ""
    foreach r $rows {
        if {[regexp {^8 create mtime ([0-9A-F]{4}) ([0-9A-F]{4})} $r -> dw tw]} { set line $r }
    }
    if {$line eq ""} { return "no create line on the screen" }
    scan $dw %x dw; scan $tw %x tw
    set Y [expr {($dw >> 9) + 1980}]; set M [expr {($dw >> 5) & 15}]; set D [expr {$dw & 31}]
    set h [expr {$tw >> 11}]; set m [expr {($tw >> 5) & 63}]; set s [expr {($tw & 31) * 2}]
    set got [expr {[days_from_civil $Y $M $D] * 86400 + $h * 3600 + $m * 60 + $s}]
    set tz $::env(M6_TZ_OFFSET)
    scan $tz {%1s%2d%2d} sign tzh tzm
    set off [expr {($tzh * 3600 + $tzm * 60) * ($sign eq "-" ? -1 : 1)}]
    set now [expr {[clock seconds] + $off}]
    set diff [expr {abs($now - $got)}]
    if {$diff > 300} { return "the stamp $Y-$M-$D $h:$m:$s is $diff s from the host's local clock" }
    puts stderr "harness: $::test: the stamp is within $diff s of the host's clock"
    # The writer's ticks.
    foreach {key label} {16K "16K writes" 4K "4K writes" 1000 "1000-byte writes"} {
        set ticks ""
        foreach r $rows {
            if {[regexp "^writer: 64K/$key in (\\d+)" $r -> v]} { set ticks $v }
        }
        if {$ticks eq ""} { return "no writer line for $label on the screen" }
        if {$ticks == 0} { return "the writer took no time for $label" }
        puts stderr [format "harness: %s: write() 64K in %s: %d ticks, %.1f KB/s (an emulator's figure: a hint)" \
            $::test $label $ticks [expr {64.0 * 60 / $ticks}]]
    }
    # The files, through the emulator's FAT code, against the pattern.
    # (The slave's synthetic partition table is one the emulator's tool does
    # not open, so big.bin, on it, is judged inside the machine alone.)
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir/tmp
    diskmanipulator chdir hda1 tmp
    if {[catch {diskmanipulator export hda1 $dir/tmp} err]} { return "export of hda1's tmp failed: $err" }
    diskmanipulator chdir hda1 /
    foreach {f inverted} {tmp/b4k.bin 1 tmp/b1000.bin 0} {
        set path [file join $dir $f]
        if {![file exists $path]} { return "$f was not exported" }
        set fh [open $path rb]
        set data [read $fh]
        close $fh
        if {[string length $data] != 65536} { return "$f is [string length $data] bytes on the image" }
        if {$data ne [pattern $inverted]} { return "$f does not hold the pattern" }
    }
    puts stderr "harness: $::test: b4k.bin and b1000.bin hold the pattern"
    # On the Turbo cartridge the block counts the commands it started:
    # the FAT accelerator's must have been asked — step 12's and step
    # 13's counts through statfs, and the allocator's next-free query
    # for step 13's 257th cluster — at least four.
    if {[info exists ::env(M6_CART)] && $::env(M6_CART) eq "turbo"} {
        binary scan [debug read_block {SD Mapper V2 m6block} 0x40 4] iu n
        if {$n < 4} { return "the block answered $n FAT accelerator commands; at least 4 were expected" }
        puts stderr "harness: $::test: the block answered $n FAT accelerator commands"
        if {!$::lies} { return "the allocator never asked the device: no lie was told" }
        puts stderr "harness: $::test: the allocator refused the device's false answer"
    }
    return ""
}
