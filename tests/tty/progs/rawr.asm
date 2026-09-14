; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; rawr — three reads of one byte each from descriptor 0, each written to
; descriptor 1: in raw mode, three keys as they come, control bytes
; included. Exits 0, or 1 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      b,3
.next:  push    bc
        xor     a
        ld      hl,buf
        ld      bc,1
        sys     SYS_READ
        jr      c,.err
        ld      a,1
        ld      hl,buf
        ld      bc,1
        sys     SYS_WRITE
        jr      c,.err
        pop     bc
        djnz    .next
        xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    db      0
