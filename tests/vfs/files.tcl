# Files the vfs test reads, written into the staging directory by
# tools/mkdisk.tcl before the import: too large or too regular to commit.
#   data/0fill.bin  a filler, so that big.bin's chain starts high enough
#                   in the FAT to cross an entry that straddles two
#                   sectors (FAT12 entry 341: byte 511-512); vfs.tcl
#                   checks that it does
#   data/big.bin    65 536 bytes, byte i = (i ^ (i >> 8)) & 0xFF
#   data/odd.txt    1001 bytes of text, not a multiple of anything
set dir [file join $::env(M6_STAGING) data]
file mkdir $dir
set fh [open [file join $dir 0fill.bin] wb]
puts -nonewline $fh [string repeat [binary format c 0] 1228800]
close $fh
set fh [open [file join $dir big.bin] wb]
set bytes {}
for {set i 0} {$i < 65536} {incr i} {
    lappend bytes [expr {($i ^ ($i >> 8)) & 0xFF}]
}
puts -nonewline $fh [binary format c* $bytes]
close $fh
set fh [open [file join $dir odd.txt] wb]
puts -nonewline $fh [string range [string repeat "the quick brown fox jumps over the lazy dog\n" 30] 0 1000]
close $fh
