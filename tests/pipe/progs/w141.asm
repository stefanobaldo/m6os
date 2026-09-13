; w141 — sleeps five ticks, then writes ten bytes to descriptor 1 and
; exits 0. With no reader on the pipe descriptor 1 names, the write ends
; it with status 141 instead.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,5
        sys     SYS_SLEEP
        ld      a,1
        ld      hl,msg
        ld      bc,10
        sys     SYS_WRITE
        xor     a
        sys     SYS_EXIT
msg:    db      "ten bytes",10
