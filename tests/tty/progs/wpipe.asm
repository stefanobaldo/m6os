; wpipe — ignores SIGPIPE, sleeps five ticks, then writes ten bytes to
; descriptor 1: with no reader on the pipe it names, the write is refused
; with EPIPE instead of ending the process. Exits 0 for EPIPE, 1 when the
; write went through, 2 for another error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGPIPE
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,5
        sys     SYS_SLEEP
        ld      a,1
        ld      hl,msg
        ld      bc,10
        sys     SYS_WRITE
        jr      c,.refused
        ld      a,1
        sys     SYS_EXIT
.refused:
        cp      E_PIPE
        jr      nz,.other
        xor     a
        sys     SYS_EXIT
.other: ld      a,2
        sys     SYS_EXIT
msg:    db      "ten bytes",10
