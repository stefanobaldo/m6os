; prod — writes 64 KB of the pattern byte i = (i ^ (i >> 8)) & FFh to
; descriptor 1 in 512-byte pieces; exits 0, or 1 when a write fails.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      de,0                    ; i
.piece: ld      hl,buf
        ld      bc,512
.fill:  ld      a,d
        xor     e
        ld      (hl),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.fill
        push    de
        ld      a,1
        ld      hl,buf
        ld      bc,512
        sys     SYS_WRITE
        pop     de
        jr      c,.err
        ld      a,d
        or      e
        jr      nz,.piece               ; until i wraps: 65536 bytes
        xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    ds      512
