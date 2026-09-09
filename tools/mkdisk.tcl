# Builds a test's disk image, run by openMSX in two steps because -hda can
# only be given at startup:
#   M6_STEP=create   no disk attached: create the image — M6_MASTER gives
#                    diskmanipulator's sizes and options (one size is one
#                    unpartitioned FAT volume, which Nextor boots; several
#                    with -nextor a Nextor partition table) — and, when
#                    M6_SLAVE is not empty, a second image for a slave
#                    device the same way
#   M6_STEP=import   -hda <image>: import the staging directory into its
#                    first volume (hda1 when partitioned, hda otherwise)
# M6_IMAGE is the image path, M6_SLAVE_IMAGE the slave's, M6_STAGING the
# directory to import.
set throttle off
set mute on
proc create {path shape} {
    file delete -force $path
    if {[catch {diskmanipulator create $path {*}$shape} err]} {
        puts stderr "mkdisk: create $path failed: $err"
        exit 1
    }
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
