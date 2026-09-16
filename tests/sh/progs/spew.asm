; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; spew N — writes six rows of dots, 480 bytes, to descriptor 1, over and
; over, until N ticks have passed (600 without N); exits 0. On the console
; each write is ~5 ms inside the kernel against a few instructions
; outside, so a tick — and the ^C it carries — nearly always finds this
; process in the resident: the case where a signal cannot be planted at
; once and is left owed, which must survive the process giving the CPU up
; at the write's return. Whole rows, so that whatever is printed after the
; process dies begins a row of its own.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,.default
        call    str_atoi
        jr      .go
.default:
        ld      hl,600
.go:    ld      (span),hl
        ld      hl,(K_TICKS)
        ld      (t0),hl
        ld      hl,buf
        ld      b,6
.row:   ld      c,79
.dot:   ld      (hl),'.'
        inc     hl
        dec     c
        jr      nz,.dot
        ld      (hl),10
        inc     hl
        djnz    .row
.loop:  ld      a,1
        ld      hl,buf
        ld      bc,480
        sys     SYS_WRITE
        jr      c,.fail
        ld      hl,(K_TICKS)
        ld      de,(t0)
        or      a
        sbc     hl,de                   ; elapsed
        ld      de,(span)
        or      a
        sbc     hl,de
        jr      c,.loop
        xor     a
        ret
.fail:  ld      a,1
        ret
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     span,2
        bss     t0,2
        bss     buf,480
