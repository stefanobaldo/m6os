; false — exits with 1. No library.
        include "kernel/kernel.inc"
        org     P0_PROG
        jr      start
        db      "m6"
        db      1
        db      0
start:  ld      a,1
        sys     SYS_EXIT
