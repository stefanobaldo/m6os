; rdeof — one read of descriptor 0: exits 7 when it returns 0 bytes (^D on
; an empty line), else with the count it returned; 1 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        xor     a
        ld      hl,buf
        ld      bc,64
        sys     SYS_READ
        jr      c,.err
        ld      a,h
        or      l
        jr      nz,.some
        ld      a,7
        sys     SYS_EXIT
.some:  ld      a,l
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    ds      64
