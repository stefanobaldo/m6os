; date — the clock, as YYYY-MM-DD HH:MM:SS. The kernel gives the date
; and time as a FAT entry holds them, with the seconds halved, so the
; seconds printed are always even; a machine without a working clock
; prints 1980-01-01 00:00:00.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   sys     SYS_TIME                ; hl = the date, de = the time
        ld      (dw),hl
        ld      (tw),de
        ld      a,h
        srl     a                       ; the year since 1980
        ld      l,a
        ld      h,0
        ld      de,1980
        add     hl,de
        ld      b,0
        call    out_dec16
        ld      a,'-'
        call    out_putc
        ld      de,(dw)
        ld      a,e
        rrca
        rrca
        rrca
        rrca
        rrca
        and     7
        ld      c,a
        ld      a,d
        and     1
        add     a,a
        add     a,a
        add     a,a
        or      c                       ; the month
        call    dec2
        ld      a,'-'
        call    out_putc
        ld      de,(dw)
        ld      a,e
        and     31                      ; the day
        call    dec2
        ld      a,' '
        call    out_putc
        ld      bc,(tw)
        ld      a,b
        srl     a
        srl     a
        srl     a                       ; the hour
        call    dec2
        ld      a,':'
        call    out_putc
        ld      bc,(tw)
        ld      a,c
        rrca
        rrca
        rrca
        rrca
        rrca
        and     7
        ld      e,a
        ld      a,b
        and     7
        add     a,a
        add     a,a
        add     a,a
        or      e                       ; the minute
        call    dec2
        ld      a,':'
        call    out_putc
        ld      bc,(tw)
        ld      a,c
        and     31
        add     a,a                     ; the seconds, halved in the entry
        call    dec2
        ld      a,10
        call    out_putc
        xor     a
        ret

; dec2 — A = 0 to 99, two digits.
dec2:   ld      c,'0'-1
.tens:  inc     c
        sub     10
        jr      nc,.tens
        add     a,10
        push    af
        ld      a,c
        call    out_putc
        pop     af
        add     a,'0'
        jp      out_putc

        include "lib/out.inc"
        m6_bss
        bss     dw,2
        bss     tw,2
