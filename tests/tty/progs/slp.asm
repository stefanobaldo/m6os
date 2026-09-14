; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; slp — sleeps ten seconds; exits 1 if it ever wakes.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,600
        sys     SYS_SLEEP
        ld      a,1
        sys     SYS_EXIT
