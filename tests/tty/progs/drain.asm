; drain — one byte from descriptor 0, in raw mode, and exits with it: the
; 03h a ^C nobody took leaves in the queue. 255 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        xor     a
        ld      hl,buf
        ld      bc,1
        sys     SYS_READ
        jr      c,.err
        ld      a,(buf)
        sys     SYS_EXIT
.err:   ld      a,255
        sys     SYS_EXIT
buf:    db      0
