# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The file the block writes through the cache, M6BLK.TST: one sector of
# pattern P1, byte i = (i & 0xFF) ^ 0x5A, put on the volume by this hook
# before tools/mkdisk.tcl imports the staging directory, behind a filler
# of 26 sectors — the eviction step reads the volume's first 25 sectors
# as misses, so the file's own must not be among them; under Nextor the
# system files put it past them. Under Nextor the loader deletes it and
# creates it again with the same bytes; from the kernel ROM the block
# finds it here, its sector as the FAT places it. Both stay outside the
# staging tree, so the import does not write them a second time.
set aside [file join $::env(M6_STAGING) .. blk.aside]
file delete -force $aside
file mkdir $aside
set fh [open [file join $aside PAD.BIN] wb]
puts -nonewline $fh [string repeat \0 [expr {26 * 512}]]
close $fh
set fh [open [file join $aside M6BLK.TST] wb]
set bytes {}
for {set i 0} {$i < 512} {incr i} { lappend bytes [expr {($i & 0xFF) ^ 0x5A}] }
puts -nonewline $fh [binary format c* $bytes]
close $fh
diskmanipulator import $target [file join $aside PAD.BIN]
diskmanipulator import $target [file join $aside M6BLK.TST]
