; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; prodf — writes 64 KB to descriptor 1 in 512-byte pieces from one
; buffer, doing nothing per byte: what the throughput step pairs with
; consf, so that the figure is the pipe's and not the programs'. Exits 0,
; or 1 when a write fails.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      b,128                   ; pieces
.piece: push    bc
        ld      a,1
        ld      hl,buf
        ld      bc,512
        sys     SYS_WRITE
        pop     bc
        jr      c,.err
        djnz    .piece
        xor     a
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
buf:    ds      512,55h
