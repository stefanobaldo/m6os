; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; sleep N — nothing, for N whole seconds: N times 60 ticks, asked of the
; kernel in pieces of at most 65 535 ticks so that no second is rounded.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,usage
        call    str_atoi
        jr      c,usage
        ld      a,(de)
        or      a
        jr      nz,usage                ; not a number to the end
        ld      de,0                    ; de:hl = N
        call    shl2                    ; 4 N
        ld      (t4),hl
        ld      (t4+2),de
        call    shl2
        call    shl2                    ; 64 N
        ld      bc,(t4)
        or      a
        sbc     hl,bc
        ld      b,h
        ld      c,l
        ld      hl,(t4+2)
        ex      de,hl
        sbc     hl,de
        ex      de,hl
        ld      h,b
        ld      l,c                     ; de:hl = 60 N
.piece: ld      a,d
        or      e
        jr      nz,.max
        ld      a,h
        or      l
        ret     z                       ; nothing left: status 0
        push    de
        sys     SYS_SLEEP
        pop     de
        ld      hl,0
        jr      .piece
.max:   push    de
        push    hl
        ld      hl,65535
        sys     SYS_SLEEP
        pop     hl
        pop     de
        ld      bc,65535
        or      a
        sbc     hl,bc
        jr      nc,.piece
        dec     de
        jr      .piece
usage:  ld      de,s_usage
        jp      err_usage

; shl2 — de:hl doubled twice.
shl2:   add     hl,hl
        rl      e
        rl      d
        add     hl,hl
        rl      e
        rl      d
        ret

s_usage: db     "sleep N",0

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     t4,4
