; pp1 — the pipe's basics, from a process: two descriptors, bytes in
; order through partial reads, EINVAL for a zero-length read, ENFILE with
; four pipes in the system (the caller holds two) — the table is looked
; at before the descriptors — EMFILE with one descriptor free and a row
; to spare, EOF once the write end is closed. Exits 0, or 11 to
; 16 naming the check that failed.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        sys     SYS_PIPE
        jp      c,.e11
        ld      a,l
        cp      3
        jp      nz,.e11                 ; the read end is the lowest free
        ld      a,h
        cp      4
        jp      nz,.e11
        ; 200 bytes of i, written at once.
        ld      hl,buf
        ld      b,200
        xor     a
.fill:  ld      (hl),a
        inc     hl
        inc     a
        djnz    .fill
        ld      a,4
        ld      hl,buf
        ld      bc,200
        sys     SYS_WRITE
        jp      c,.e12
        ld      de,200
        or      a
        sbc     hl,de
        jp      nz,.e12
        ; Read back in four pieces of fifty, in order.
        ld      e,0                     ; the byte expected next
.r:     push    de
        ld      a,3
        ld      hl,rbuf
        ld      bc,50
        sys     SYS_READ
        pop     de
        jp      c,.e13
        ld      a,l
        cp      50
        jp      nz,.e13
        ld      hl,rbuf
        ld      b,50
.cmp:   ld      a,(hl)
        cp      e
        jp      nz,.e13
        inc     hl
        inc     e
        djnz    .cmp
        ld      a,e
        cp      200
        jr      nz,.r
        ; A zero-length read: EINVAL.
        ld      a,3
        ld      hl,rbuf
        ld      bc,0
        sys     SYS_READ
        jp      nc,.e14
        cp      E_INVAL
        jp      nz,.e14
        ; A second pipe: 5 and 6. A third: the caller holds two, so the
        ; table is full — ENFILE.
        sys     SYS_PIPE
        jp      c,.e15
        ld      a,l
        cp      5
        jp      nz,.e15
        sys     SYS_PIPE
        jp      nc,.e15
        cp      E_NFILE
        jp      nz,.e15
        ; Both ends of the second closed: a row free again. A file on 5
        ; and another on 6: one descriptor free with a row to spare —
        ; EMFILE. Then 6 closed: the pipe takes 6 and 7.
        ld      a,6
        sys     SYS_CLOSE
        jp      c,.e15
        ld      a,5
        sys     SYS_CLOSE
        jp      c,.e15
        ld      hl,p_file
        xor     a
        sys     SYS_OPEN
        jp      c,.e15
        cp      5
        jp      nz,.e15
        ld      hl,p_file
        xor     a
        sys     SYS_OPEN
        jp      c,.e15
        cp      6
        jp      nz,.e15
        sys     SYS_PIPE
        jp      nc,.e15
        cp      E_MFILE
        jp      nz,.e15
        ld      a,6
        sys     SYS_CLOSE
        jp      c,.e15
        sys     SYS_PIPE
        jp      c,.e15
        ld      a,l
        cp      6
        jp      nz,.e15
        ; EOF: the first pipe's write end closed, its read end empty.
        ld      a,4
        sys     SYS_CLOSE
        jp      c,.e16
        ld      a,3
        ld      hl,rbuf
        ld      bc,50
        sys     SYS_READ
        jp      c,.e16
        ld      a,h
        or      l
        jp      nz,.e16
        ld      a,3
        ld      hl,rbuf
        ld      bc,50
        sys     SYS_READ
        jp      c,.e16
        ld      a,h
        or      l
        jp      nz,.e16
        xor     a
        sys     SYS_EXIT
.e11:   ld      a,11
        sys     SYS_EXIT
.e12:   ld      a,12
        sys     SYS_EXIT
.e13:   ld      a,13
        sys     SYS_EXIT
.e14:   ld      a,14
        sys     SYS_EXIT
.e15:   ld      a,15
        sys     SYS_EXIT
.e16:   ld      a,16
        sys     SYS_EXIT
p_file: db      "/notm6.bin",0
buf:    ds      200
rbuf:   ds      50
