; ign — ignores SIGINT, sleeps half a second, exits 5: the survivor of a
; ^C.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,30
        sys     SYS_SLEEP
        ld      a,5
        sys     SYS_EXIT
