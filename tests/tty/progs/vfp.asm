; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; vfp — vforks: the child sleeps half a second and exits 4; the parent,
; asleep in vfork meanwhile, is what the test kills — it must die on
; waking, never reach the exit below. 2 if it does, 3 if vfork failed.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        sys     SYS_VFORK
        jr      c,.no
        ld      a,h
        or      l
        jr      nz,.parent
        ld      hl,30
        sys     SYS_SLEEP
        ld      a,4
        sys     SYS_EXIT
.parent:
        ld      a,2
        sys     SYS_EXIT
.no:    ld      a,3
        sys     SYS_EXIT
