; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; dosarg — dosenter's refusals, each before anything is written: a place
; for the layer's body that is not a buffer's start, that leaves the block
; cache too few buffers, that lies outside the buffers or does not hold
; the body; a body that leaves page 0; a segment that is not the
; caller's. Every one must come back, with its errno, and the cache must
; be whole afterwards — the harness counts the lent headers. Prints
; "dosarg ok", or the step that failed.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1

; try where, length, body, errno — one refusal
    macro try Q1,Q2,Q3,Q4
        ld      a,(seg)
        ld      hl,Q3
        ld      bc,Q2
        ld      de,Q1
        sys     SYS_DOSENTER
        ld      b,Q4
        call    expect
    endm

main:   sys     SYS_SEGALLOC
        jp      c,.nomem                ; nothing free: nothing to try
        ld      a,l
        ld      (seg),a
        try     ST_BUF+1, 100, P0_PROG, E_INVAL             ; 1: not a 512
        try     ST_BUF+7*512+256, 100, P0_PROG, E_INVAL     ; 2: nor this
        try     ST_BUF+(BUF_MIN-1)*512, 100, P0_PROG, E_INVAL ; 3: too few left
        try     ST_BUF-512, 100, P0_PROG, E_INVAL           ; 4: below them
        try     ST_BUF+(BUF_N-1)*512, 513, P0_PROG, E_INVAL ; 5: does not hold it
        try     ST_BUF+(BUF_N-1)*512, 0101h, 3F00h, E_FAULT ; 6: past page 0
        ld      a,(seg)
        sys     SYS_SEGFREE
        xor     a
        ld      (seg),a                 ; 7: segment 0 is not this process's
        try     ST_BUF+(BUF_N-1)*512, 100, P0_PROG, E_INVAL
        ld      hl,s_ok
        call    out_puts
        xor     a
        ret
.nomem: ld      hl,s_nomem
        call    out_puts
        xor     a
        ret

; expect — CF and A from the call, B = the errno wanted; the step counted.
expect: ld      hl,step
        inc     (hl)
        jr      nc,.bad                 ; it must not succeed
        cp      b
        ret     z
.bad:   ld      hl,s_fail
        call    out_puts
        ld      a,(step)
        ld      l,a
        ld      h,0
        ld      b,0
        call    out_dec16
        ld      a,10
        call    out_putc
        ld      a,(seg)
        or      a
        jr      z,.exit
        sys     SYS_SEGFREE
.exit:  ld      a,1
        jp      lib_exit

s_ok:   db      "dosarg ok",10,0
s_nomem: db     "dosarg ok (no segment to try with)",10,0
s_fail: db      "dosarg fail ",0
step:   db      0
seg:    db      0
        include "lib/out.inc"
        m6_bss
