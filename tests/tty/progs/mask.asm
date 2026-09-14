; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; mask — exits with its own signal mask, read back through procinfo: what
; it inherited from whoever started it.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        sys     SYS_GETPID
        ld      a,l
        ld      hl,buf
        sys     SYS_PROCINFO
        jr      c,.err
        ld      a,(buf+P_SIZE+PX_SIGIGN)
        sys     SYS_EXIT
.err:   ld      a,255
        sys     SYS_EXIT
buf:    ds      PROCINFO_SIZE
