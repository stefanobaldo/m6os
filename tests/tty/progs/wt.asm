; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; wt — starts /bin/slpi and waits for it: blocked in waitpid for ten
; seconds, long enough for a ^C to find it there — and slpi ignores the
; ^C, so it is left an orphan for the test to kill. Exits 1 if the wait
; ever returns, 2 if slpi could not be started.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,p_slp
        ld      de,av_slp
        ld      bc,m_inh
        sys     SYS_SPAWNV
        jr      c,.no
        ld      b,0
        sys     SYS_WAITPID
        ld      a,1
        sys     SYS_EXIT
.no:    ld      a,2
        sys     SYS_EXIT
p_slp:  db      "/bin/slpi",0
av_slp: dw      p_slp,0
m_inh:  db      0FFh,0FFh,0FFh
