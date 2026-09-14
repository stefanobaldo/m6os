; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; rdl — reads one line from descriptor 0 (canonical: edited, closed by
; RET) and writes it to descriptor 1 as it came; exits 0, or 1 on an
; error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        xor     a
        ld      hl,buf
        ld      bc,64
        sys     SYS_READ
        jr      c,.err
        ld      b,h
        ld      c,l
        ld      a,1
        ld      hl,buf
        sys     SYS_WRITE
        jr      c,.err
        xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    ds      64
