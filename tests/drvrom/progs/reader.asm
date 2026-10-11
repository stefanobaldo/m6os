; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; reader — the program the drvrom test spawns from the pattern volume: it
; reads /PATTERN.BIN over and over, 4K at a time into a buffer on a
; 256-byte boundary — whole sectors, straight from the driver into this
; page — and checks every byte against the pattern (byte i of the file's
; sector n is the low byte of 7 n + i, xor 55h in the sector's second
; half). It never ends by itself: the harness presses ^C into one of its
; driver calls and it dies of the signal at the call's return. A byte
; that differs ends it with 1, a failed call with 2.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        include "drvrom/layout.inc"
        m6_header 1
start:
        ld      hl,s_file
        ld      a,O_RDONLY
        sys     SYS_OPEN
        jp      c,fail2
        ld      (fd),a
again:  ld      a,PT_K
        ld      (sec),a
loop:   ld      a,(fd)
        ld      hl,buf
        ld      bc,4096
        sys     SYS_READ
        jp      c,fail2
        ld      a,h
        or      l
        jr      z,eof
        ld      hl,buf
        ld      b,8
.sector:
        push    bc
        ld      a,(sec)
        ld      d,a
        add     a,a
        add     a,a
        add     a,a
        sub     d                       ; 7 n
        ld      d,a
        ld      e,0
.lo:    ld      a,d
        add     a,e
        cp      (hl)
        jr      nz,fail1
        inc     hl
        inc     e
        jr      nz,.lo
.hi:    ld      a,d
        add     a,e
        xor     55h
        cp      (hl)
        jr      nz,fail1
        inc     hl
        inc     e
        jr      nz,.hi
        ld      a,(sec)
        inc     a
        ld      (sec),a
        pop     bc
        djnz    .sector
        jr      loop
eof:    ld      a,(fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,fail2
        jr      again
fail1:  ld      a,1
        sys     SYS_EXIT
fail2:  ld      a,2
        sys     SYS_EXIT

s_file: db      "/PATTERN.BIN",0
fd:     db      0
sec:    db      0
        ALIGN   256
buf:    ds      4096
