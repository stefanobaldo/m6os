; cons — reads descriptor 0 to its end and checks every byte against the
; pattern prod writes; exits 0 for 65536 matching bytes, 1 on a wrong
; byte, 2 on a wrong count, 3 on a read error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      de,0                    ; i
        xor     a
        ld      (wrapped),a
.rd:    push    de
        xor     a
        ld      hl,buf
        ld      bc,512
        sys     SYS_READ
        pop     de
        jr      c,.err
        ld      a,h
        or      l
        jr      z,.eof
        ld      b,h
        ld      c,l
        ld      hl,buf
.chk:   ld      a,d
        xor     e
        cp      (hl)
        jr      nz,.bad
        inc     hl
        inc     de
        ld      a,d
        or      e
        jr      nz,.nw
        ld      a,1
        ld      (wrapped),a
.nw:    dec     bc
        ld      a,b
        or      c
        jr      nz,.chk
        jr      .rd
.eof:   ld      a,d
        or      e
        jr      nz,.count
        ld      a,(wrapped)
        or      a
        jr      z,.count
        xor     a
        sys     SYS_EXIT
.bad:   ld      a,1
        sys     SYS_EXIT
.count: ld      a,2
        sys     SYS_EXIT
.err:   ld      a,3
        sys     SYS_EXIT
wrapped: db     0
buf:    ds      512
