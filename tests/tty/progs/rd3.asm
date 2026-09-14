; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; rd3 — reads three bytes of a line, then the rest, writing each piece to
; descriptor 1: exits with the ticks that passed between the two reads —
; 0 when the rest of the line was waiting and the second read did not
; block. 1 on an error.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        xor     a
        ld      hl,buf
        ld      bc,3
        sys     SYS_READ
        jr      c,.err
        ld      b,h
        ld      c,l
        ld      a,1
        ld      hl,buf
        sys     SYS_WRITE
        jr      c,.err
        ld      hl,(K_TICKS)
        ld      (t0),hl
        xor     a
        ld      hl,buf
        ld      bc,61
        sys     SYS_READ
        jr      c,.err
        ld      b,h
        ld      c,l
        ld      a,1
        ld      hl,buf
        sys     SYS_WRITE
        jr      c,.err
        ld      hl,(K_TICKS)
        ld      de,(t0)
        or      a
        sbc     hl,de
        ld      a,l
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
t0:     dw      0
buf:    ds      64
