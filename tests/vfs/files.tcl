# Files the vfs test reads, written by tools/mkdisk.tcl before it imports
# the staging directory: too large or too regular to commit.
#   data/0fill.bin  a filler, so that big.bin's chain starts high enough
#                   in the FAT to cross an entry that straddles two
#                   sectors (FAT12 entry 341: its two bytes are 511 and
#                   512 of the table); vfs.tcl checks that it does
#   data/big.bin    65 536 bytes, byte i = (i ^ (i >> 8)) & 0xFF
#   data/odd.txt    1001 bytes of text, not a multiple of anything
#
# The filler and big.bin go on the volume from here, in this order, and
# stay out of the staging tree: the import walks that tree in the host's
# directory order — which differs between the machines this runs on — and
# whichever of the two it met first would decide where big.bin lands. Put
# on an empty volume in a known order, they land at computable clusters:
# the data directory takes cluster 2, the filler clusters 3 to 333 (331
# clusters of 4096 bytes, this volume's), and big.bin's sixteen clusters
# 334 to 349 — so entry 341 is crossed, and crossed in the middle of the
# chain rather than at its end.
set staging $::env(M6_STAGING)
set dir [file join $staging data]
file mkdir $dir

# Outside the staging tree, so the import does not write them a second
# time and move them.
set aside [file join [file dirname $staging] vfs.data]
file delete -force $aside
file mkdir $aside

set fh [open [file join $aside 0fill.bin] wb]
puts -nonewline $fh [string repeat [binary format c 0] [expr {331 * 4096}]]
close $fh
set fh [open [file join $aside big.bin] wb]
set bytes {}
for {set i 0} {$i < 65536} {incr i} {
    lappend bytes [expr {($i ^ ($i >> 8)) & 0xFF}]
}
puts -nonewline $fh [binary format c* $bytes]
close $fh

diskmanipulator mkdir $target data
diskmanipulator chdir $target data
diskmanipulator import $target [file join $aside 0fill.bin] \
                               [file join $aside big.bin]
diskmanipulator chdir $target /

set fh [open [file join $dir odd.txt] wb]
puts -nonewline $fh [string range [string repeat "the quick brown fox jumps over the lazy dog\n" 30] 0 1000]
close $fh
