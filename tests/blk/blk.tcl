# The harness's half of the blk test. After the verdict: the boot listing
# on the screen against the partition tables of the two images read from
# outside the machine, the file the program wrote through the cache read
# back from the master's first volume, and the RTC line against the host's
# clock. The report stays in the log on a pass too.
set show_screen 1

# One expected listing line per volume, from an image file: the MBR's
# entries 1-4 in order, a type 05h entry's chain of EBRs, or — with no
# partition of ours — the boot sector as one volume. The same walk the
# kernel does, written independently.
proc sector {fh n} {
    seek $fh [expr {$n * 512}]
    return [read $fh 512]
}
proc entry {sec i} {
    # status, CHS (3), type, CHS (3), first sector, sector count
    binary scan [string range $sec [expr {0x1BE + 16*$i}] [expr {0x1BE + 16*$i + 15}]] \
        cux3cux3iuiu status type first count
    return [list $type $first $count]
}
proc volumes {path dev} {
    set fh [open $path rb]
    set out {}
    set sec0 [sector $fh 0]
    set found 0
    for {set i 0} {$i < 4} {incr i} {
        lassign [entry $sec0 $i] type first count
        if {$type == 5} {
            set ext $first
            set ebr $first
            set n 0
            while {1} {
                set s [sector $fh $ebr]
                lassign [entry $s 0] t f c
                incr n
                if {$t in {1 4 6 14} && $f != 0 && $c != 0} {
                    lappend out [list "$dev.1" "e$n" $t [expr {$c / 2}]]
                    incr found
                }
                lassign [entry $s 1] lt lf lc
                if {$lt != 5 || $n >= 9} break
                set ebr [expr {$ext + $lf}]
            }
        } elseif {$type in {1 4 6 14} && $first != 0 && $count != 0} {
            lappend out [list "$dev.1" "p[expr {$i + 1}]" $type [expr {$count / 2}]]
            incr found
        }
    }
    if {!$found} {
        binary scan [string range $sec0 0x13 0x14] su total16
        binary scan [string range $sec0 0x20 0x23] iu total32
        set total [expr {$total16 != 0 ? $total16 : $total32}]
        lappend out [list "$dev.1" "--" 0 [expr {$total / 2}]]
    }
    close $fh
    return $out
}

# days since 1970-01-01 of a civil date (Howard Hinnant's algorithm), for
# a clock without `clock format`.
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
    # The listing: every /mnt/ line, in order.
    set expected [concat [volumes $::env(M6_IMAGE) 1] [volumes $::env(M6_SLAVE_IMAGE) 2]]
    set got {}
    set names {}
    foreach r $rows {
        if {[regexp {^/mnt/([a-h])\s+(.+?)\s+(\d\.\d) (p\d|e\d|--)\s+([0-9A-F]{2})\s+(\d+) KB( /)?\s*$} $r -> letter name devlun label type kb root]} {
            lappend got [list $devlun $label [expr 0x$type] $kb]
            lappend names $name
            if {$root ne ""} { set rootletter $letter }
        }
    }
    if {$got ne $expected} {
        return "listing is {$got}, the images say {$expected}"
    }
    if {[lsort -unique $names] ne [list [lindex $names 0]]} {
        return "the driver's name differs between lines: $names"
    }
    if {![info exists rootletter] || $rootletter ne "a"} {
        return "the boot volume is not /mnt/a"
    }
    # The file, from the master's first volume.
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda1 $dir} err]} {
        return "export from the image failed: $err"
    }
    set f ""
    foreach e [glob -nocomplain -directory $dir -types f *] {
        if {[string equal -nocase [file tail $e] "M6BLK.TST"]} { set f $e; break }
    }
    if {$f eq ""} { return "M6BLK.TST is not on the volume" }
    set fh [open $f rb]
    set data [read $fh]
    close $fh
    if {[string length $data] != 512} {
        return "M6BLK.TST is [string length $data] bytes, not 512"
    }
    binary scan $data cu* bytes
    for {set i 0} {$i < 512} {incr i} {
        set want [expr {($i & 0xFF) ^ 0xA5}]
        if {[lindex $bytes $i] != $want} {
            return [format "M6BLK.TST byte %d is %02X, expected %02X" $i [lindex $bytes $i] $want]
        }
    }
    puts stderr "harness: $::test: M6BLK.TST holds the sector written through the cache"
    # The RTC: the machine's clock is the host's local time; M6_TZ_OFFSET
    # (+hhmm, from date +%z) turns the host's epoch into local seconds.
    set line ""
    foreach r $rows {
        if {[regexp {^12 rtc (\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)} $r -> Y M D h m s]} {
            set line $r
        }
    }
    if {$line eq ""} { return "no RTC line on the screen" }
    scan $Y %d Y; scan $M %d M; scan $D %d D; scan $h %d h; scan $m %d m; scan $s %d s
    set got [expr {[days_from_civil $Y $M $D] * 86400 + $h * 3600 + $m * 60 + $s}]
    set tz $::env(M6_TZ_OFFSET)
    scan $tz {%1s%2d%2d} sign tzh tzm
    set off [expr {($tzh * 3600 + $tzm * 60) * ($sign eq "-" ? -1 : 1)}]
    set now [expr {[clock seconds] + $off}]
    set diff [expr {abs($now - $got)}]
    if {$diff > 300} {
        return "RTC read $Y-$M-$D $h:$m:$s is $diff s from the host's local clock"
    }
    puts stderr "harness: $::test: RTC within $diff s of the host's clock"
    return ""
}
