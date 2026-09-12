# Run by tools/run-test.sh after the import, with the image closed: what no
# importer writes. The root entry RO.TXT of the master's first volume gets
# the read-only attribute, so that the test can be refused by it. The
# partition table is walked by its own rules; the boot sector's fields as
# the specification lays them out.
set path $::env(M6_IMAGE)
set fh [open $path rb+]
proc sector {n} { seek $::fh [expr {$n * 512}]; return [read $::fh 512] }
binary scan [string range [sector 0] 0x1C6 0x1C9] iu first
set bs [sector $first]
binary scan [string range $bs 0x0E 0x0F] su rsvd
binary scan [string range $bs 0x10 0x10] cu nfats
binary scan [string range $bs 0x11 0x12] su rootent
binary scan [string range $bs 0x16 0x17] su fatsz
set root [expr {$first + $rsvd + $nfats * $fatsz}]
set found 0
for {set s 0} {$s < $rootent / 16 && !$found} {incr s} {
    set sec [sector [expr {$root + $s}]]
    for {set i 0} {$i < 16} {incr i} {
        set e [string range $sec [expr {$i * 32}] [expr {$i * 32 + 31}]]
        if {[string range $e 0 10] eq "RO      TXT"} {
            binary scan [string index $e 11] cu attr
            seek $fh [expr {($root + $s) * 512 + $i * 32 + 11}]
            puts -nonewline $fh [binary format c [expr {$attr | 0x01}]]
            set found 1
            break
        }
    }
}
close $fh
if {!$found} { puts stderr "patch: RO.TXT not found in the root"; exit 1 }
puts stderr "patch: RO.TXT made read-only"
exit 0
