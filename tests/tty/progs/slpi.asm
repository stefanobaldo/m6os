; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; slpi — ignores SIGINT and sleeps ten seconds: a child that outlives the
; ^C that kills its parent, left an orphan asleep for kill to end. Exits 1
; if it ever wakes.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,600
        sys     SYS_SLEEP
        ld      a,1
        sys     SYS_EXIT
