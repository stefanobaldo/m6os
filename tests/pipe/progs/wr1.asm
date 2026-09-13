; wr1 — writes its first argument and a newline to descriptor 1; exits 0,
; or 1 without an argument.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,c
        cp      2
        jr      c,.none
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        call    m6_puts_hl
        m6_puts s_nl
        xor     a
        sys     SYS_EXIT
.none:  ld      a,1
        sys     SYS_EXIT
        m6_proglib
s_nl:   db      10,0
