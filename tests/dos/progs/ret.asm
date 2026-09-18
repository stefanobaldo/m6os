; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; ret — a line, then ret with the stack as it came: the program ends.
        include "dos/progs/dos.inc"
        org     100h
        d_puts  s
        ret
s:      db      "ret",13,10,"$"
