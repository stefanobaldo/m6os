; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; gen — writes the numbers 1 to 100 to descriptor 1, one per line.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,1
.n:     push    hl
        call    m6_dec16
        m6_puts s_nl
        pop     hl
        inc     hl
        ld      a,l
        cp      101
        jr      nz,.n
        xor     a
        sys     SYS_EXIT
        m6_proglib
s_nl:   db      10,0
