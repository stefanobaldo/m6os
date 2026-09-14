; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; ignall — ignores every signal that can be ignored, sleeps two seconds,
; exits 6: only SIGKILL ends it sooner.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      a,SIGPIPE
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      a,SIGTERM
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,120
        sys     SYS_SLEEP
        ld      a,6
        sys     SYS_EXIT
