; true — exits with 0. No library: the header, and a return into the
; kernel's exit stub.
        include "kernel/kernel.inc"
        org     P0_PROG
        jr      start
        db      "m6"
        db      1
        db      0
start:  ret
