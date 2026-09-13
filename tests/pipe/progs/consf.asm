; consf — reads descriptor 0 to its end, counting bytes and checking the
; first byte of each read only; exits 0 for 65536 bytes, 1 on a wrong
; byte, 2 on a wrong count, 3 on a read error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      de,0                    ; bytes so far, low 16
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
        ld      a,(buf)
        cp      55h
        jr      nz,.bad
        add     hl,de
        ex      de,hl
        jr      nc,.rd
        ld      a,1
        ld      (wrapped),a
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
