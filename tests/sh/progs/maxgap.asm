; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; maxgap N — reads the kernel's tick count in a loop for N ticks, never
; yielding, and prints the largest gap between two consecutive readings:
; alone that is 1; beside one other runnable process 2, the turn
; alternating; and anything beyond is time that process held the CPU
; inside a syscall — the delay a key's echo would have waited.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,.default
        call    str_atoi
        jr      .go
.default:
        ld      hl,300
.go:    ld      (span),hl
        ld      hl,(K_TICKS)
        ld      (t0),hl
        ld      (last),hl
        ld      hl,0
        ld      (gap),hl
.loop:  ld      hl,(K_TICKS)
        ld      de,(last)
        ld      (last),hl
        push    hl
        or      a
        sbc     hl,de                   ; hl = the gap
        ld      de,(gap)
        or      a
        sbc     hl,de                   ; the new gap less the largest
        jr      c,.nogap
        jr      z,.nogap
        add     hl,de
        ld      (gap),hl
.nogap: pop     hl
        ld      de,(t0)
        or      a
        sbc     hl,de                   ; elapsed
        ld      de,(span)
        or      a
        sbc     hl,de
        jr      c,.loop
        ld      hl,s_gap
        call    out_puts
        ld      hl,(gap)
        ld      b,0
        call    out_dec16
        ld      a,10
        call    out_putc
        xor     a
        ret
s_gap:  db      "gap ",0
        include "lib/out.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     span,2
        bss     t0,2
        bss     last,2
        bss     gap,2
