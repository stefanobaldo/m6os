; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; exit7 — _TERM with code 7: the shell reports [7].
        include "dos/progs/dos.inc"
        org     100h
        ld      b,7
        ld      c,_TERM
        call    BDOS
