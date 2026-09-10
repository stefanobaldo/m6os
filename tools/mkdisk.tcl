# Builds a test's disk image, run by openMSX in two steps because -hda can
# only be given at startup:
#   M6_STEP=create   no disk attached: create the image — M6_MASTER gives
#                    diskmanipulator's sizes and options (one size is one
#                    unpartitioned FAT volume, which Nextor boots; several
#                    with -nextor a Nextor partition table; -fat16max the
#                    synthetic image below) — and, when M6_SLAVE is not
#                    empty, a second image for a slave device the same way
#   M6_STEP=import   -hda <image>: import the staging directory into its
#                    first volume (hda1 when partitioned, hda otherwise)
# M6_IMAGE is the image path, M6_SLAVE_IMAGE the slave's, M6_STAGING the
# directory to import.
set throttle off
set mute on
proc create {path shape} {
    file delete -force $path
    if {$shape eq "-fat16max"} {
        fat16max $path
        return
    }
    if {[catch {diskmanipulator create $path {*}$shape} err]} {
        puts stderr "mkdisk: create $path failed: $err"
        exit 1
    }
}

# A shape diskmanipulator cannot produce: one FAT16 partition whose file
# allocation table is 256 sectors, which is what a nearly full FAT16 has
# and the largest the format allows. A formatter picks the cluster size
# from the volume's size and never lands here on an image small enough for
# a test, so the boot sector is written by hand. The fields are consistent
# with each other: 65501 clusters of one sector need 256 sectors of FAT,
# and the partition's sector count is what the BPB declares. The volume
# holds no files -- the enumeration reads the BPB and nothing else, and no
# test opens it.
proc fat16max {path} {
    set clusters 65501
    set fatsz 256
    set rsvd 1
    set nfats 2
    set rootent 512
    set spc 1
    set rootsec [expr {$rootent * 32 / 512}]
    set partsec [expr {$rsvd + $nfats * $fatsz + $rootsec + $clusters}]
    set first 1
    set total [expr {$first + $partsec + 53}]

    set fh [open $path wb]
    # Sector 0: a partition table with one entry, type 0Eh (FAT16 LBA).
    set mbr [binary format a446 ""]
    append mbr [binary format c8 {0 0 0 0 0x0E 0 0 0}]
    append mbr [binary format ii $first $partsec]
    append mbr [binary format a48 ""]
    append mbr [binary format cc 0x55 0xAA]
    puts -nonewline $fh $mbr

    # The partition's boot sector, field by field at its own offset.
    set bs [binary format ccc 0xEB 0x3C 0x90]
    append bs [binary format a8 "M6TEST  "]
    append bs [binary format s 512]             ;# 0Bh bytes per sector
    append bs [binary format c $spc]            ;# 0Dh sectors per cluster
    append bs [binary format s $rsvd]           ;# 0Eh reserved sectors
    append bs [binary format c $nfats]          ;# 10h number of FATs
    append bs [binary format s $rootent]        ;# 11h root entries
    append bs [binary format s 0]               ;# 13h total sectors, 16-bit
    append bs [binary format c 0xF8]            ;# 15h media descriptor
    append bs [binary format s $fatsz]          ;# 16h sectors per FAT
    append bs [binary format ss 63 255]         ;# 18h geometry
    append bs [binary format i $first]          ;# 1Ch hidden sectors
    append bs [binary format i $partsec]        ;# 20h total sectors, 32-bit
    append bs [binary format cc 0x80 0]         ;# 24h drive, reserved
    append bs [binary format c 0x29]            ;# 26h extended boot signature
    append bs [binary format i 0x4D365446]      ;# 27h volume id
    append bs [binary format a11 "M6 FAT16MAX"]
    append bs [binary format a8 "FAT16   "]
    append bs [binary format a[expr {510 - [string length $bs]}] ""]
    append bs [binary format cc 0x55 0xAA]
    seek $fh [expr {$first * 512}]
    puts -nonewline $fh $bs

    # Both FATs start with the media descriptor and the end-of-chain mark,
    # so the volume is an empty FAT16 and not 256 sectors of zero.
    for {set i 0} {$i < $nfats} {incr i} {
        seek $fh [expr {($first + $rsvd + $i * $fatsz) * 512}]
        puts -nonewline $fh [binary format cccc 0xF8 0xFF 0xFF 0xFF]
    }

    # The image's last byte, so its length is the total the LUN reports.
    seek $fh [expr {$total * 512 - 1}]
    puts -nonewline $fh [binary format c 0]
    close $fh
}
switch $::env(M6_STEP) {
    create {
        create $::env(M6_IMAGE) $::env(M6_MASTER)
        if {$::env(M6_SLAVE) ne ""} {
            create $::env(M6_SLAVE_IMAGE) $::env(M6_SLAVE)
        }
    }
    import {
        # A partitioned image has volumes hda1, hda2, ...; an unpartitioned
        # one is hda itself.
        set target hda
        if {[llength $::env(M6_MASTER)] > 1} { set target hda1 }
        if {[catch {diskmanipulator import $target $::env(M6_STAGING)} err]} {
            puts stderr "mkdisk: import into $target failed: $err"
            exit 1
            return
        }
        puts stderr "mkdisk: [file tail $::env(M6_IMAGE)] $target contents:\n[diskmanipulator dir $target]"
    }
    default {
        puts stderr "mkdisk: M6_STEP must be create or import"
        exit 1
        return
    }
}
exit 0
