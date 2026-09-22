; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hptr — where a program keeps what it hands the system must not matter.
; The same calls are made with their arguments — two paths, a file info
; block, a buffer to fill, a name and a value, a transfer buffer — laid
; out from a base, and the base moves: low memory; 8100h, wholly inside
; page 2; and five bases that put each argument in turn across 8000h.
; The first round's answers are kept and every later round must give the
; same, byte for byte; a pointer the system returns must point into the
; program's own argument, wherever that is. The step on a failure is the
; round times 20 plus the call.
        include "dosf/progs/dosf.inc"

; The arguments, as offsets from the base.
A_P1            equ 0           ; 16: a path
A_P2            equ 16          ; 16: a second one
A_FIB           equ 32          ; 64: a file info block
A_OUT           equ 96          ; 64: a buffer the system fills
A_NAME          equ 160         ; 8: an environment name
A_VAL           equ 168         ; 8: its value
A_END           equ 176

; p_de off, p_hl off, p_ix off — the register -> base + off.
    macro p_hl Q1
        ld      hl,(base)
        ld      de,Q1
        add     hl,de
    endm
    macro p_de Q1
        p_hl    Q1
        ex      de,hl
    endm
    macro p_ix Q1
        ld      ix,(base)
        ld      de,Q1
        add     ix,de
    endm
; p_hl_keep — HL -> the buffer at the base; DE kept.
    macro p_hl_keep
        push    de
        p_hl    A_OUT
        pop     de
    endm
; t_st n — the step: the round's twenty plus n.
    macro t_st Q1
        ld      a,(round)
        add     a,Q1
        ld      (t_step),a
    endm

        org     100h
        ld      hl,bases
.round: ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,d
        or      e
        jp      z,t_ok
        ld      (base),de
        push    hl
        call    calls
        pop     hl
        ld      a,(round)
        add     a,20
        ld      (round),a
        jr      .round

; calls — one round: the arguments laid out from the base, then the calls.
calls:  ld      hl,(base)
        ex      de,hl
        ld      hl,args
        ld      bc,A_END
        ldir
        t_st    1                       ; _CREATE, the path in DE
        p_de    A_P1
        xor     a
        ld      b,0
        d_fn    _CREATE
        d_ok
        ld      a,b
        ld      (hnd),a
        t_st    2                       ; _WRITE from the buffer, as laid out
        p_de    A_OUT
        ld      hl,8
        ld      a,(hnd)
        ld      b,a
        d_fn    _WRITE
        d_ok
        d_hlis  8
        ld      a,(hnd)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        t_st    3                       ; _RENAME: DE the file, HL the new name
        p_hl    A_P2
        push    hl
        p_de    A_P1
        pop     hl
        d_fn    _RENAME
        d_ok
        t_st    4                       ; _FFIRST: DE the path, IX the block
        p_ix    A_FIB
        p_de    A_P2
        ld      b,0
        d_fn    _FFIRST
        d_ok
        p_hl    A_FIB+1                 ; the name found, in the block
        ld      de,n_p2
        call    d_streq
        jp      nz,t_fail
        t_st    5                       ; _FNEXT: the block again, no more
        p_ix    A_FIB
        d_fn    _FNEXT
        d_err   D_NOFIL
        t_st    6                       ; _WPATH: the buffer filled, HL into it
        p_de    A_OUT
        d_fn    _WPATH
        d_ok
        push    hl
        p_de    A_OUT
        pop     hl
        push    hl
        or      a
        sbc     hl,de                   ; the last item's offset in it
        ld      (r_off),hl
        ld      a,h
        or      a
        jp      nz,t_fail               ; not a pointer into the buffer
        pop     hl
        ld      de,n_p2
        call    d_streq
        jp      nz,t_fail
        ld      ix,k_wpath
        call    same
        t_st    7                       ; _OPEN and _READ into the buffer
        p_de    A_P2
        xor     a
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (hnd),a
        p_hl    A_OUT
        ld      b,8
.clr:   ld      (hl),0
        inc     hl
        djnz    .clr
        p_de    A_OUT
        ld      hl,8
        ld      a,(hnd)
        ld      b,a
        d_fn    _READ
        d_ok
        d_hlis  8
        p_hl    A_OUT
        ld      de,args+A_OUT
        ld      bc,8
        call    d_memeq
        jp      nz,t_fail
        ld      a,(hnd)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        t_st    8                       ; _PARSE: DE and HL into the string
        p_de    A_P2
        ld      b,0
        d_fn    _PARSE
        d_ok
        push    hl
        push    de
        p_hl    A_P2+8                  ; its terminator
        pop     de
        or      a
        sbc     hl,de
        jp      nz,t_fail
        p_de    A_P2                    ; its last item: all of it
        pop     hl
        or      a
        sbc     hl,de
        jp      nz,t_fail
        t_st    9                       ; _PFILE: DE the string, HL eleven bytes
        p_hl    A_OUT
        push    hl
        p_de    A_P2
        pop     hl
        d_fn    _PFILE
        d_ok
        push    de
        p_hl    A_P2+8
        pop     de
        or      a
        sbc     hl,de
        jp      nz,t_fail
        p_hl    A_OUT
        ld      de,n_p2x
        ld      bc,11
        call    d_memeq
        jp      nz,t_fail
        t_st    10                      ; _GETCD: the buffer filled
        p_de    A_OUT
        ld      b,0
        d_fn    _GETCD
        d_ok
        ld      ix,k_getcd
        call    same
        t_st    11                      ; _DPARM: 32 bytes, DE as it went in
        p_de    A_OUT
        ld      l,0
        d_fn    _DPARM
        d_ok
        push    de
        p_hl    A_OUT
        pop     de
        or      a
        sbc     hl,de
        jp      nz,t_fail
        ld      ix,k_dparm
        call    same
        t_st    12                      ; _EXPLAIN: a message
        p_de    A_OUT
        ld      b,D_NOFIL
        d_fn    _EXPLAIN
        d_ok
        ld      ix,k_explain
        call    same
        t_st    13                      ; _SENV: HL the name, DE the value
        p_hl    A_NAME
        push    hl
        p_de    A_VAL
        pop     hl
        d_fn    _SENV
        d_ok
        t_st    14                      ; _GENV: HL the name, DE B bytes
        p_hl    A_OUT
        ld      (hl),'?'
        p_hl    A_NAME
        push    hl
        p_de    A_OUT
        pop     hl
        ld      b,64
        d_fn    _GENV
        d_ok
        p_hl    A_OUT
        ld      de,args+A_VAL
        call    d_streq
        jp      nz,t_fail
        t_st    15                      ; _FENV: item 2, HL B bytes — after
        p_hl    A_OUT                   ; PROGRAM; with no tail there is no
        ld      de,2                    ; PARAMETERS
        ld      b,64
        d_fn    _FENV
        d_ok
        p_hl    A_OUT
        ld      de,args+A_NAME
        call    d_streq
        jp      nz,t_fail
        t_st    16                      ; the name unset, the file deleted
        p_hl    A_NAME
        ld      de,s_empty
        d_fn    _SENV
        d_ok
        p_de    A_P2
        d_fn    _DELETE
        d_ok
        ret

; same — IX -> a kept answer (a flag, then 64 bytes): the buffer at the
; base must equal it, or becomes it in the first round.
same:   ld      a,(ix+0)
        or      a
        jr      nz,.cmp
        ld      (ix+0),1
        push    ix
        pop     de
        inc     de
        p_hl_keep
        ld      bc,64
        ldir
        ret
.cmp:   push    ix
        pop     de
        inc     de
        p_hl_keep
        ld      bc,32                   ; what every answer here defines
        call    d_memeq
        jp      nz,t_fail
        ret

        d_lib   "hptr"
base:   dw      0
round:  db      0
hnd:    db      0
r_off:  dw      0
bases:  dw      1000h                   ; low memory
        dw      8100h                   ; page 2
        dw      8000h-4-A_P1            ; the first path across 8000h
        dw      8000h-4-A_P2            ; the second
        dw      8000h-4-A_FIB           ; the block
        dw      8000h-4-A_OUT           ; the buffer
        dw      8000h-4-A_NAME          ; the name
        dw      0
args:   db      "PTRA.TMP",0,0,0,0,0,0,0,0
        db      "PTRB.TMP",0,0,0,0,0,0,0,0
        ds      64,0
        db      "transfer"
        ds      56,0
        db      "HPTRV",0,0,0
        db      "abc",0,0,0,0,0
n_p2:   db      "PTRB.TMP",0
n_p2x:  db      "PTRB    TMP"
s_empty: db     0
k_wpath: ds     65,0
k_getcd: ds     65,0
k_dparm: ds     65,0
k_explain: ds   65,0
