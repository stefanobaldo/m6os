; two — a two-page program: exits with a byte that lives in its second
; page, so that page was loaded too.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 2
start:
        ld      a,(mark)
        sys     SYS_EXIT
        block   4100h-$
mark:   db      33
