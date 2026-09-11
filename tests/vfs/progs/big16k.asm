; big16k — a program of 16 000 bytes, near the most a one-page program can
; be (16 102 with an empty argument vector: the page less P0_PROG, the
; frame and the block). On entry it reads the tick counter, prints it, and
; exits with 16; whoever started it printed the counter before the exec,
; and the difference is what the exec cost.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,(K_TICKS)
        push    hl
        m6_puts s_t1
        pop     hl
        call    m6_dec16
        m6_puts s_nl
        ld      a,16
        sys     SYS_EXIT
        m6_proglib
s_t1:   db      "big16k: t1 ",0
s_nl:   db      10,0
        block   P0_PROG+16000-$,0A5h
