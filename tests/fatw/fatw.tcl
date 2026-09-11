# The harness's half of the fatw test. After the verdict: the stamp the
# created file got, against the host's clock; the writer's ticks, turned
# into KB/s for the log — a hint in the emulator, the gate's line on the
# bench; and the files the writer left, exported through the emulator's
# own FAT code and compared byte by byte with what they should hold. The
# two copies of every table and the checker's verdict are the run
# script's, once the emulator has closed the images.
set show_screen 1

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
    return ""
}
