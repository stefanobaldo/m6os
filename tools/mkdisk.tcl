# Builds a test's disk image, run by openMSX in two steps because -hda can
# only be given at startup:
#   M6_STEP=create   no disk attached: create the image (one size, so one
#                    unpartitioned FAT volume, which Nextor boots)
#   M6_STEP=import   -hda <image>: import the staging directory into it
# M6_IMAGE is the image path, M6_STAGING the directory to import.
set throttle off
set mute on
switch $::env(M6_STEP) {
    create {
        file delete -force $::env(M6_IMAGE)
        if {[catch {diskmanipulator create $::env(M6_IMAGE) 2M} err]} {
            puts stderr "mkdisk: create failed: $err"
            exit 1
            return
        }
    }
    import {
        if {[catch {diskmanipulator import hda $::env(M6_STAGING)} err]} {
            puts stderr "mkdisk: import failed: $err"
            exit 1
            return
        }
        puts stderr "mkdisk: [file tail $::env(M6_IMAGE)] contents:\n[diskmanipulator dir hda]"
    }
    default {
        puts stderr "mkdisk: M6_STEP must be create or import"
        exit 1
        return
    }
}
exit 0
