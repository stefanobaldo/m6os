; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; tlf — ttyline with a buffer in page 3, which a program may not name:
; exits with the errno it is refused with, or 0 if it was not.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,0C000h
        ld      bc,1
        sys     SYS_TTYLINE
        jr      c,.no
        xor     a
.no:    sys     SYS_EXIT
