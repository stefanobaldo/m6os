# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Run by tools/run-test.sh after the import, with the image closed: what
# no importer writes. The master's third volume (the second of the
# extended chain, /mnt/c) is made to claim four more clusters than its
# partition holds — its boot sector's total raised, the partition entry
# left alone — so that a cluster can be addressed whose sectors lie past
# the volume's end, which the block layer refuses before the driver is
# called. Three files are written into its empty root for the runs
# program:
#   BADLINK.BIN  two clusters, the second linked to 1, which no chain
#                may hold; size 8192
#   FARR.BIN     a cluster inside the partition linked to one wholly
#                past its end; size 4096
#   FAR.BIN      the last cluster wholly inside, alone; size 512 — the
#                cluster after it, straddling the end, left free for the
#                allocator to hand out
# Both table copies are written. The volume is never checked by fsck.
set path $::env(M6_IMAGE)
set fh [open $path rb+]
proc sector {n} { seek $::fh [expr {$n * 512}]; return [read $::fh 512] }
# A partition entry's type, first sector and count.
proc pentry {sec i} {
    set e [string range $sec [expr {0x1BE + 16*$i}] [expr {0x1BE + 16*$i + 15}]]
    binary scan [string index $e 4] cu type
    binary scan [string range $e 8 11] iu first
    binary scan [string range $e 12 15] iu count
    return [list $type $first $count]
}
# The extended container, then the second EBR of its chain.
set s0 [sector 0]
set ext ""
for {set i 0} {$i < 4} {incr i} {
    lassign [pentry $s0 $i] type first count
    if {$type in {5 15}} { set ext $first }
}
if {$ext eq ""} { puts stderr "patch: no extended partition"; exit 1 }
set ebr1 [sector $ext]
lassign [pentry $ebr1 1] t2 f2 c2
if {$t2 ni {5 15}} { puts stderr "patch: the extended chain has one volume"; exit 1 }
set ebr2 [sector [expr {$ext + $f2}]]
lassign [pentry $ebr2 0] vtype vrel vcount
set vfirst [expr {$ext + $f2 + $vrel}]
# The volume's geometry.
set bs [sector $vfirst]
binary scan [string range $bs 0x0D 0x0D] cu spc
binary scan [string range $bs 0x0E 0x0F] su rsvd
binary scan [string range $bs 0x10 0x10] cu nfats
binary scan [string range $bs 0x11 0x12] su rootent
binary scan [string range $bs 0x13 0x14] su total
binary scan [string range $bs 0x16 0x17] su fatsz
set root [expr {$rsvd + $nfats * $fatsz}]
set data [expr {$root + $rootent * 32 / 512}]
set fatents [expr {$fatsz * 512 * 8 / 12}]
# The last cluster wholly inside the partition, L; L+1 straddles its end,
# L+2 lies past it. All three must have table entries and stay FAT12.
set L [expr {($vcount - $data) / $spc + 1}]
while {$data + ($L - 2) * $spc + $spc > $vcount} { incr L -1 }
set F [expr {$L + 1}]
set G [expr {$L + 2}]
set newtotal [expr {$data + ($G - 1) * $spc}]
set newclusters [expr {($newtotal - $data) / $spc}]
if {$G > $fatents - 1 || $newclusters >= 4085} {
    puts stderr "patch: cannot address cluster $G on this volume"; exit 1
}
# FAT12 entries, both copies.
proc fat12get {c} {
    set o [expr {$c + $c / 2}]
    seek $::fh [expr {($::vfirst + $::rsvd) * 512 + $o}]
    binary scan [read $::fh 2] su w
    return [expr {($c & 1) ? ($w >> 4) : ($w & 0xFFF)}]
}
proc fat12set {c v} {
    set o [expr {$c + $c / 2}]
    for {set n 0} {$n < $::nfats} {incr n} {
        set at [expr {($::vfirst + $::rsvd + $n * $::fatsz) * 512 + $o}]
        seek $::fh $at
        binary scan [read $::fh 2] su w
        if {$c & 1} { set w [expr {($w & 0x000F) | ($v << 4)}] } else { set w [expr {($w & 0xF000) | $v}] }
        seek $::fh $at
        puts -nonewline $::fh [binary format s $w]
    }
}
set B1 [expr {$L - 5}]
set B2 [expr {$L - 4}]
set A [expr {$L - 1}]
foreach c [list $B1 $B2 $A $L $F $G] {
    if {[fat12get $c] != 0} { puts stderr "patch: cluster $c is not free"; exit 1 }
}
fat12set $B1 $B2
fat12set $B2 1
fat12set $A $G
fat12set $G 0xFFF
fat12set $L 0xFFF
# The boot sector's total.
seek $fh [expr {$vfirst * 512 + 0x13}]
puts -nonewline $fh [binary format s $newtotal]
# The root's first three entries, which must be free.
set rootsec [expr {$vfirst + $root}]
set rs [sector $rootsec]
foreach i {0 1 2} {
    binary scan [string index $rs [expr {$i * 32}]] cu first
    if {$first != 0} { puts stderr "patch: the root is not empty"; exit 1 }
}
proc dirent {name11 clus size} {
    return [binary format a11cx10sssi $name11 0x20 0 0x5021 $clus $size]
}
seek $fh [expr {$rootsec * 512}]
puts -nonewline $fh [dirent "BADLINK BIN" $B1 8192]
puts -nonewline $fh [dirent "FARR    BIN" $A 4096]
puts -nonewline $fh [dirent "FAR     BIN" $L 512]
close $fh
puts stderr "patch: volume at $vfirst claims $newclusters clusters over $vcount sectors; BADLINK.BIN $B1->$B2->1, FARR.BIN $A->$G, FAR.BIN $L; $F free"
exit 0
