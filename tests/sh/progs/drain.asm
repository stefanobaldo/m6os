; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; drain — reads descriptor 0 to its end and prints nothing: the last
; stage of the pipelines the bench script runs between its two stamped
; ones, so that only two lines reach the screen.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   xor     a
        call    in_open
.loop:  call    in_fill
        ret     c
        ld      a,b
        or      c
        jr      nz,.loop
        ret
        include "lib/in.inc"
        m6_bss
