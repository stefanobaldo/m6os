# The harness's half of the vfs test. After the verdict: the mount lines on
# the screen against the boot sectors of the volumes, read from the images
# outside the machine; the sizes the program printed against the staging
# directory; the big file's chain against the FAT, which must cross an
# entry that straddles two sectors for the test to have exercised that
# path; and the reader's ticks, turned into KB/s for the log — a hint in
# the emulator, the gate on the bench. The report stays in the log.
set show_screen 1

proc sector {fh n} {
    seek $fh [expr {$n * 512}]
    return [read $fh 512]
}
proc entry {sec i} {
    binary scan [string range $sec [expr {0x1BE + 16*$i}] [expr {0x1BE + 16*$i + 15}]] \
        cux3cux3iuiu status type first count
    return [list $type $first $count]
}
# The first sector of every volume of an image, in the kernel's order:
# the four primary entries, a type 05h entry's chain, or sector 0 alone.
proc firsts {path} {
    set fh [open $path rb]
    set out {}
    set sec0 [sector $fh 0]
    for {set i 0} {$i < 4} {incr i} {
        lassign [entry $sec0 $i] type first count
        if {$type in {5 15}} {                 ;# 05h CHS, 0Fh LBA
            set ext $first
            set ebr $first
            set n 0
            while {1} {
                set s [sector $fh $ebr]
                lassign [entry $s 0] t f c
                incr n
                if {$t in {1 4 6 14} && $f != 0 && $c != 0} { lappend out [expr {$ebr + $f}] }
                lassign [entry $s 1] lt lf lc
                if {$lt ni {5 15} || $n >= 9} break
                set ebr [expr {$ext + $lf}]
            }
        } elseif {$type in {1 4 6 14} && $first != 0 && $count != 0} {
            lappend out $first
        }
    }
    if {![llength $out]} { lappend out 0 }
    close $fh
    return $out
}
# The BPB of the volume at sector first: a dict of what the mount table
# holds, computed as the specification says.
proc bpb {path first} {
    set fh [open $path rb]
    set bs [sector $fh $first]
    close $fh
    binary scan [string range $bs 0x0D 0x0D] cu spc
    binary scan [string range $bs 0x0E 0x0F] su rsvd
    binary scan [string range $bs 0x10 0x10] cu nfats
    binary scan [string range $bs 0x11 0x12] su rootent
    binary scan [string range $bs 0x13 0x14] su total16
    binary scan [string range $bs 0x16 0x17] su fatsz
    binary scan [string range $bs 0x20 0x23] iu total32
    set total [expr {$total16 != 0 ? $total16 : $total32}]
    set root [expr {$rsvd + $nfats * $fatsz}]
    set rootn [expr {$rootent * 32 / 512}]
    set data [expr {$root + $rootn}]
    set clusters [expr {($total - $data) / $spc}]
    set type [expr {$clusters < 4085 ? 12 : 16}]
    return [dict create spc $spc fat $rsvd root $root rootn $rootn data $data \
        clusters $clusters type $type fatsz $fatsz nfats $nfats first $first]
}
# The FAT12 entry for cluster c, from the image.
proc fat12 {fh b c} {
    set o [expr {$c + $c / 2}]
    seek $fh [expr {([dict get $b first] + [dict get $b fat]) * 512 + $o}]
    binary scan [read $fh 2] su w
    return [expr {($c & 1) ? ($w >> 4) : ($w & 0xFFF)}]
}
# The 32-byte entries of a directory: the root area, or a chain.
proc direntries {fh b clus} {
    set out {}
    set first [dict get $b first]
    if {$clus == 0} {
        for {set i 0} {$i < [dict get $b rootn]} {incr i} {
            append out [sector $fh [expr {$first + [dict get $b root] + $i}]]
        }
    } else {
        set c $clus
        while {$c >= 2 && $c < 0xFF8} {
            set s [expr {$first + [dict get $b data] + ($c - 2) * [dict get $b spc]}]
            for {set i 0} {$i < [dict get $b spc]} {incr i} {
                append out [sector $fh [expr {$s + $i}]]
            }
            set c [fat12 $fh $b $c]
        }
    }
    return $out
}
# The entry named (eleven bytes, FAT form) in a directory: its first
# cluster and size, or empty.
proc find {fh b clus name11} {
    set d [direntries $fh $b $clus]
    for {set i 0} {$i < [string length $d]} {incr i 32} {
        set e [string range $d $i [expr {$i + 31}]]
        binary scan $e a11cu n attr
        if {[string index $n 0] eq "\x00"} break
        if {$n eq $name11 && ($attr & 0x08) == 0} {
            binary scan [string range $e 26 27] su clus
            binary scan [string range $e 28 31] iu size
            return [list $clus $size]
        }
    }
    return {}
}

proc post_verdict {} {
    set rows [split [get_screen] \n]
    # The mount lines against the images' boot sectors.
    set expected {}
    foreach f [firsts $::env(M6_IMAGE)] { lappend expected [bpb $::env(M6_IMAGE) $f] }
    foreach f [firsts $::env(M6_SLAVE_IMAGE)] { lappend expected [bpb $::env(M6_SLAVE_IMAGE) $f] }
    set got {}
    foreach r $rows {
        if {[regexp {^mnt ([a-h]) fat(12|16) spc (\d+) fat (\d+) root (\d+) data (\d+) clusters (\d+)} \
                $r -> letter type spc fat root data clusters]} {
            lappend got [list $type $spc $fat $root $data $clusters]
        }
    }
    set want {}
    foreach b $expected {
        lappend want [list [dict get $b type] [dict get $b spc] [dict get $b fat] \
            [dict get $b root] [dict get $b data] [dict get $b clusters]]
    }
    if {$got ne $want} { return "mount table is {$got}, the boot sectors say {$want}" }
    puts stderr "harness: $::test: [llength $got] volumes mounted as the boot sectors say"
    # The sizes the program printed.
    set line ""
    foreach r $rows { if {[regexp {^9 stat /bin/hello size (\d+)} $r -> size]} { set line $r } }
    if {$line eq ""} { return "no stat line on the screen" }
    set real [file size [file join $::env(M6_STAGING) bin hello]]
    if {$size != $real} { return "stat says hello is $size bytes, the file is $real" }
    # The big file's chain: it must cross a straddling FAT12 entry.
    set b [lindex $expected 0]
    if {[dict get $b type] != 12} { return "the boot volume is not FAT12" }
    set fh [open $::env(M6_IMAGE) rb]
    set data [find $fh $b 0 "DATA       "]
    if {$data eq ""} { close $fh; return "no DATA directory in the root" }
    set big [find $fh $b [lindex $data 0] "BIG     BIN"]
    if {$big eq ""} { close $fh; return "no BIG.BIN in DATA" }
    lassign $big c size
    if {$size != 65536} { close $fh; return "BIG.BIN is $size bytes on the image" }
    set chain {}
    set straddles 0
    while {$c >= 2 && $c < 0xFF8} {
        lappend chain $c
        set next [fat12 $fh $b $c]
        if {(($c + $c / 2) & 0x1FF) == 0x1FF && $next < 0xFF8} { incr straddles }
        set c $next
    }
    close $fh
    if {!$straddles} {
        return "BIG.BIN's chain ([lindex $chain 0]..[lindex $chain end], [llength $chain] clusters) crosses no straddling FAT12 entry"
    }
    puts stderr "harness: $::test: BIG.BIN at cluster [lindex $chain 0], [llength $chain] clusters, $straddles straddling entry read"
    # The reader's ticks: KB/s for the log.
    set line ""
    foreach r $rows { if {[regexp {^reader: 64K in (\d+) ticks} $r -> ticks]} { set line $r } }
    if {$line eq ""} { return "no reader line on the screen" }
    if {$ticks == 0} { return "the reader took no time" }
    puts stderr [format "harness: %s: read() 64K in %d ticks: %.1f KB/s (an emulator's figure: a hint)" \
        $::test $ticks [expr {64.0 * 60 / $ticks}]]
    # The exec's ticks: the caller's before the call, the program's on entry.
    set t0 ""
    set t1 ""
    foreach r $rows {
        if {[regexp {^exec: t0 (\d+)} $r -> v]} { scan $v %d t0 }
        if {[regexp {^big16k: t1 (\d+)} $r -> v]} { set t1 $v }
    }
    if {$t0 eq "" || $t1 eq ""} { return "no exec timing lines on the screen" }
    set dt [expr {($t1 - $t0) & 0xFFFF}]
    puts stderr [format "harness: %s: exec of a 16K program in %d ticks, %.0f ms (an emulator's figure: a hint)" \
        $::test $dt [expr {$dt * 1000.0 / 60}]]
    return ""
}
