; rdf — reads /big.bin in 4 KB pieces, forever, seeking back to the start
; at its end: a process that is inside a long syscall nearly all the
; time, for a ^C to land in. Exits 2 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,p_big
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
.rd:    ld      a,(fd)
        ld      hl,buf
        ld      bc,4096
        sys     SYS_READ
        jr      c,.err
        ld      a,h
        or      l
        jr      nz,.rd
        ld      a,(fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jr      c,.err
        jr      .rd
.err:   ld      a,2
        sys     SYS_EXIT
p_big:  db      "/big.bin",0
fd:     db      0
buf:    ds      4096
