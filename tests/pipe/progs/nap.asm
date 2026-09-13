; nap — sleeps the number of ticks its first argument says, then exits
; with that number as its status (its low byte). Without an argument:
; status 0 at once.
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
        call    m6_atoi
        push    hl
        sys     SYS_SLEEP
        pop     hl
        ld      a,l
        sys     SYS_EXIT
.none:  xor     a
        sys     SYS_EXIT
        m6_proglib
