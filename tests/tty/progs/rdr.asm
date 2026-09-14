; rdr — blocks in a read of the keyboard; exits 1 if the read ever returns.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        xor     a
        ld      hl,buf
        ld      bc,64
        sys     SYS_READ
        ld      a,1
        sys     SYS_EXIT
buf:    ds      64
