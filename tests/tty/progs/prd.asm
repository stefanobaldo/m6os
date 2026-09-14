; prd — reads descriptor 0 to its end and exits with how many reads
; returned bytes: one, for the 256 bytes a killed writer left in a pipe.
; 255 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      c,0
.rd:    push    bc
        xor     a
        ld      hl,buf
        ld      bc,256
        sys     SYS_READ
        pop     bc
        jr      c,.err
        ld      a,h
        or      l
        jr      z,.end
        inc     c
        jr      .rd
.end:   ld      a,c
        sys     SYS_EXIT
.err:   ld      a,255
        sys     SYS_EXIT
buf:    ds      256
