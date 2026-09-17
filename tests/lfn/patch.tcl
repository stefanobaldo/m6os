# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Run by tools/run-test.sh after the import and mtools, with the image
# closed: the two long-name cases no writer makes on purpose, in /LFN of
# the master's first volume. The short entry ORPHAN.TXT is marked deleted,
# which orphans the chain before it; the chain part before MYFILE~1.TXT
# gets a wrong checksum (MyFile Two.txt, whose alias that is). Both are what the host's FAT checker rejects, so
# every byte changed is written to <image>.patch, offset and old value,
# for check.sh to put back before the checker runs.
set path $::env(M6_IMAGE)
set fh [open $path rb+]
proc sector {n} { seek $::fh [expr {$n * 512}]; return [read $::fh 512] }
binary scan [string range [sector 0] 0x1C6 0x1C9] iu first
set bs [sector $first]
binary scan [string range $bs 0x0D 0x0D] cu spc
binary scan [string range $bs 0x0E 0x0F] su rsvd
binary scan [string range $bs 0x10 0x10] cu nfats
binary scan [string range $bs 0x11 0x12] su rootent
binary scan [string range $bs 0x16 0x17] su fatsz
set root [expr {$first + $rsvd + $nfats * $fatsz}]
set data [expr {$root + $rootent * 32 / 512}]

# find <first sector> <count> <11-byte name>: the entry's byte offset in
# the image, or -1.
proc find {sec n name} {
    for {set s 0} {$s < $n} {incr s} {
        set buf [sector [expr {$sec + $s}]]
        for {set i 0} {$i < 16} {incr i} {
            set e [string range $buf [expr {$i * 32}] [expr {$i * 32 + 31}]]
            if {[string range $e 0 10] eq $name} {
                return [expr {($sec + $s) * 512 + $i * 32}]
            }
        }
    }
    return -1
}
set log [open "$path.patch" w]
proc poke {off value} {
    seek $::fh $off
    binary scan [read $::fh 1] cu old
    puts $::log "$off $old"
    seek $::fh $off
    puts -nonewline $::fh [binary format c $value]
}
set lfn [find $root [expr {$rootent / 16}] "LFN        "]
if {$lfn < 0} { puts stderr "patch: no LFN directory in the root"; exit 1 }
seek $fh [expr {$lfn + 26}]
binary scan [read $fh 2] su clus
set dsec [expr {$data + ($clus - 2) * $spc}]
set orphan [find $dsec $spc "ORPHAN  TXT"]
set my2 [find $dsec $spc "MYFILE~1TXT"]
if {$orphan < 0 || $my2 < 0} { puts stderr "patch: ORPHAN.TXT or MYFILE~1.TXT not in /LFN"; exit 1 }
poke $orphan 0xE5
poke [expr {$my2 - 32 + 13}] 0x00
close $log
close $fh
puts stderr "patch: ORPHAN.TXT deleted under its chain, MYFILE~1.TXT's chain given a wrong checksum"
exit 0
