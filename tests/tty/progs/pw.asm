; pw — writes 300 bytes to descriptor 1: into a pipe nobody drains, the
; write fills the pipe and blocks on the rest. Exits 1 if it ever
; returns, 2 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,1
        ld      hl,buf
        ld      bc,300
        sys     SYS_WRITE
        ld      a,1
        jr      nc,.exit
        ld      a,2
.exit:  sys     SYS_EXIT
buf:    ds      300,33h
