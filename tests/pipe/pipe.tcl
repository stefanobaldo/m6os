# The harness's half of the pipe test. After the verdict: the pipeline's
# output file, exported through the emulator's own FAT code and compared
# with what the three programs must produce; the two timed steps, turned
# into figures for the log — hints in the emulator, the gate's lines on
# the bench; and the clock's reading against the host's local clock.
set show_screen 1

proc days_from_civil {y m d} {
    if {$m <= 2} { incr y -1 }
    set era [expr {($y >= 0 ? $y : $y - 399) / 400}]
    set yoe [expr {$y - $era * 400}]
    set doy [expr {(153 * ($m + ($m > 2 ? -3 : 9)) + 2) / 5 + $d - 1}]
    set doe [expr {$yoe * 365 + $yoe / 4 - $yoe / 100 + $doy}]
    return [expr {$era * 146097 + $doe - 719468}]
}

proc post_verdict {} {
    set rows [split [get_screen] \n]
    # The pipe's throughput: 64 KB in N ticks.
    set ticks ""
    foreach r $rows { if {[regexp {^7 pipe: 64K in (\d+) ticks} $r -> v]} { set ticks $v } }
    if {$ticks eq ""} { return "no pipe throughput line on the screen" }
    if {$ticks == 0} { return "the pipe took no time" }
    puts stderr [format "harness: %s: 64K through a pipe in %d ticks: %.1f KB/s (an emulator's figure: a hint)" \
        $::test $ticks [expr {64.0 * 60 / $ticks}]]
    # spawnv's latency: sixty in N ticks.
    set ticks ""
    foreach r $rows { if {[regexp {^11 spawnv: 60 in (\d+) ticks} $r -> v]} { set ticks $v } }
    if {$ticks eq ""} { return "no spawnv timing line on the screen" }
    puts stderr [format "harness: %s: spawnv + waitpid of a one-sector program: %.1f ms each (an emulator's figure: a hint)" \
        $::test [expr {$ticks * 1000.0 / 60 / 60}]]
    # The clock: FAT date and time words, against the host's local clock.
    set line ""
    foreach r $rows {
        if {[regexp {^16 procinfo, time ([0-9A-F]{4}) ([0-9A-F]{4})} $r -> dw tw]} { set line $r }
    }
    if {$line eq ""} { return "no time line on the screen" }
    scan $dw %x dw; scan $tw %x tw
    set Y [expr {($dw >> 9) + 1980}]; set M [expr {($dw >> 5) & 15}]; set D [expr {$dw & 31}]
    set h [expr {$tw >> 11}]; set m [expr {($tw >> 5) & 63}]; set s [expr {($tw & 31) * 2}]
    set got [expr {[days_from_civil $Y $M $D] * 86400 + $h * 3600 + $m * 60 + $s}]
    set tz $::env(M6_TZ_OFFSET)
    scan $tz {%1s%2d%2d} sign tzh tzm
    set off [expr {($tzh * 3600 + $tzm * 60) * ($sign eq "-" ? -1 : 1)}]
    set now [expr {[clock seconds] + $off}]
    set diff [expr {abs($now - $got)}]
    if {$diff > 300} { return "time says $Y-$M-$D $h:$m:$s, $diff s from the host's local clock" }
    puts stderr "harness: $::test: time is within $diff s of the host's clock"
    # The pipeline's output, through the emulator's FAT code.
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda1 $dir} err]} { return "export of hda1 failed: $err" }
    set path [file join $dir out.txt]
    if {![file exists $path]} { return "out.txt was not exported" }
    set fh [open $path rb]
    set data [read $fh]
    close $fh
    if {$data ne "2500\n"} { return "out.txt holds [string length $data] bytes: {$data}, not 2500" }
    puts stderr "harness: $::test: out.txt holds the sum of the odd numbers to 100"
    return ""
}
