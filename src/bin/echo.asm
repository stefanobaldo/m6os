; echo [-n] word... — the words, one blank between them, and a LF unless
; the first word is exactly -n. Reads argv itself: no options library, so
; the file stays one sector.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      a,10
        ld      (nl),a
        ld      a,b
        or      c
        jr      z,.end                  ; no vector at all
        dec     bc                      ; bc = words after argv[0]
        inc     hl
        inc     hl                      ; hl -> argv[1]
        ld      a,b
        or      c
        jr      z,.done
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        dec     hl
        ld      a,(de)
        cp      '-'
        jr      nz,.words
        inc     de
        ld      a,(de)
        cp      'n'
        jr      nz,.words
        inc     de
        ld      a,(de)
        or      a
        jr      nz,.words
        ld      (nl),a
        inc     hl
        inc     hl
        dec     bc
.words: ld      a,b
        or      c
        jr      z,.done
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        push    bc
        ex      de,hl
        call    out_puts
        pop     bc
        pop     hl
        dec     bc
        ld      a,b
        or      c
        jr      z,.done
        ld      a,' '
        call    out_putc
        jr      .words
.done:  ld      a,(nl)
        or      a
        jr      z,.end
        call    out_putc
.end:   xor     a
        ret
        include "lib/out.inc"
        m6_bss
        bss     nl,1
