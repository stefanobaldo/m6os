; sum — reads lines of decimal numbers from descriptor 0 to its end and
; writes their total to descriptor 1 as a decimal and a newline. Exits 0;
; 1 on an I/O error.
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
        ld      c,l
        ld      a,b
        or      c
        jr      z,.done
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
        ld      bc,0                    ; the total
.line:  ld      a,(hl)
        or      a
        jr      z,.end
        push    bc
        call    m6_atoi
        pop     bc
        add     hl,bc
        ld      b,h
        ld      c,l
        ex      de,hl
        inc     hl                      ; past the newline
        jr      .line
.end:   ld      h,b
        ld      l,c
        call    m6_dec16
        m6_puts s_nl
        xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
        m6_proglib
s_nl:   db      10,0
ptr:    dw      0
BUFLEN  equ     4096
buf:    ds      BUFLEN
