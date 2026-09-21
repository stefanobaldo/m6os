; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; filler — the fatw test's volume-filling process, three pages, started
; from the volume with spawnv: what it does is in the comment below, as it
; was when it lived inside the test's block.
        include "kernel/kernel.inc"
        include "m6prog.inc"
O_CW        equ O_CREAT|O_WRONLY
U_PAGE1     equ 4000h           ; page 1, 16K
; u_filler — three pages: /mnt/b/fill.bin written 16K at a time from page
; 1 until the volume is full: a short write and then E_NOSPC, or E_NOSPC
; outright. Prints the KB that fitted. Exits 0, or the check that failed.
        m6_header 3
start:
        ld      hl,.path
        ld      a,O_CW
        sys     SYS_OPEN
        jr      c,.x1
        ld      (.fd),a
        ld      hl,0
        ld      (.kb),hl
.w:     ld      a,(.fd)
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        jr      c,.err
        ld      bc,16384
        or      a
        sbc     hl,bc
        jr      nz,.short
        ld      hl,(.kb)
        ld      de,16
        add     hl,de
        ld      (.kb),hl
        jr      .w
.short: ld      a,(.fd)                 ; short: the next one is refused
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        jr      nc,.x3
.err:   cp      E_NOSPC
        jr      nz,.x2
        ld      hl,(.kb)
        ld      de,.digits+4
        ld      b,5
.dig:   push    bc
        ld      bc,10
        call    .div
        add     a,'0'
        ld      (de),a
        dec     de
        pop     bc
        djnz    .dig
        ld      a,1
        ld      hl,.line
        ld      bc,.linelen
        sys     SYS_WRITE
        ld      a,(.fd)
        sys     SYS_CLOSE
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    ld      a,2
        sys     SYS_EXIT
.x3:    ld      a,3
        sys     SYS_EXIT
; .div — HL = HL / BC, A = the remainder (BC < 256).
.div:   push    de
        ld      d,0
        ld      e,16
.bit:   add     hl,hl
        rl      d
        ld      a,d
        sub     c
        jr      c,.no
        ld      d,a
        inc     l
.no:    dec     e
        jr      nz,.bit
        ld      a,d
        pop     de
        ret
.path:  db      "/mnt/b/fill.bin",0
.line:  db      "filler: "
.digits: db     "00000"
        db      " KB and full",10
.linelen equ    $-.line
.fd:    db      0
.kb:    dw      0
