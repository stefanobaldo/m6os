; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; mkdir dir... — each directory made, its parent existing; a failure is
; reported and the next one follows.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,usage
.loop:  push    hl
        sys     SYS_MKDIR
        pop     de
        call    c,err_file
        call    arg_next
        jr      nc,.loop
        ld      a,(lib_status)
        ret
usage:  ld      de,s_usage
        jp      err_usage
s_usage: db     "mkdir dir...",0

        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
