; clear — a form feed to the output: the console clears the screen and
; homes the cursor. No library: the header, one write, and exit.
        include "kernel/kernel.inc"
        org     P0_PROG
        jr      start
        db      "m6"
        db      1
        db      0
start:  ld      a,1
        ld      hl,ff
        ld      bc,1
        sys     SYS_WRITE
        ld      a,0
        jr      nc,.exit
        inc     a
.exit:  sys     SYS_EXIT
ff:     db      12
