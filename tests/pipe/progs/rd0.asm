; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; rd0 — copies descriptor 0 to descriptor 1 until the end; exits 0, or 1
; on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
.rd:    xor     a
        ld      hl,buf
        ld      bc,512
        sys     SYS_READ
        jr      c,.err
        ld      a,h
        or      l
        jr      z,.end
        ld      b,h
        ld      c,l
        ld      a,1
        ld      hl,buf
        sys     SYS_WRITE
        jr      c,.err
        jr      .rd
.end:   xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    ds      512
