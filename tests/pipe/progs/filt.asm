; filt — reads lines of decimal numbers from descriptor 0 to its end and
; writes to descriptor 1 the lines whose number is odd. Exits 0; 1 on an
; I/O error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,buf
        ld      (ptr),hl
.rd:    ld      hl,buf+BUFLEN
        ld      de,(ptr)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; room left
        ld      a,b
        or      c
        jr      z,.done                 ; full: what came is what is used
        ld      hl,(ptr)
        xor     a
        sys     SYS_READ
        jr      c,.err
        ld      a,h
        or      l
        jr      z,.done
        ld      de,(ptr)
        add     hl,de
        ld      (ptr),hl
        jr      .rd
.done:  ld      hl,(ptr)
        ld      (hl),0
        ld      hl,buf
.line:  ld      a,(hl)
        or      a
        jr      z,.end
        push    hl
        call    m6_atoi                 ; hl = the number, de -> its end
        pop     bc                      ; bc = the line's start
        bit     0,l
        jr      z,.skip
        inc     de                      ; past the newline
        push    de
        ex      de,hl
        or      a
        sbc     hl,bc                   ; hl = the line's length
        ld      d,h
        ld      e,l
        ld      h,b
        ld      l,c
        ld      b,d
        ld      c,e
        ld      a,1
        sys     SYS_WRITE
        pop     hl
        jr      c,.err
        jr      .line
.skip:  ex      de,hl
        inc     hl
        jr      .line
.end:   xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
        m6_proglib
ptr:    dw      0
BUFLEN  equ     4096
buf:    ds      BUFLEN
