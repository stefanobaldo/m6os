; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hfind — the searches: a directory of files, a sub-directory and a
; hidden file, found by pattern and by attribute, two searches
; interleaved, a search from a FIB naming the directory with the whole
; path read back, a new entry from a template, and a FIB handed to open
; and to delete.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; T, its files, SUB, a hidden one
        ld      de,s_t
        ld      b,10h
        call    mk
        ld      de,s_a1
        ld      b,0
        call    mkf
        ld      de,s_a2
        ld      b,0
        call    mkf
        ld      de,s_b1
        ld      b,0
        call    mkf
        ld      de,s_sub
        ld      b,10h
        call    mk
        ld      de,s_h
        ld      b,2
        call    mkf
        d_step  2                       ; *.*: the three files
        ld      de,s_tall
        ld      b,0
        call    count
        cp      3
        jp      nz,t_fail
        d_step  3                       ; A?.TXT: two
        ld      de,s_taq
        ld      b,0
        call    count
        cp      2
        jp      nz,t_fail
        d_step  4                       ; with directories: ., .., SUB too
        ld      de,s_tall
        ld      b,10h
        call    count
        cp      6
        jp      nz,t_fail
        d_step  5                       ; with hidden ones: H.TXT too
        ld      de,s_tall
        ld      b,2
        call    count
        cp      4
        jp      nz,t_fail
        d_step  6                       ; two searches, interleaved
        ld      de,s_tastar
        ld      b,0
        ld      ix,fib1
        d_fn    _FFIRST
        d_ok
        ld      hl,fib1+1
        ld      de,n_a1
        call    d_streq
        jp      nz,t_fail
        ld      de,s_tbstar
        ld      b,0
        ld      ix,fib2
        d_fn    _FFIRST
        d_ok
        ld      hl,fib2+1
        ld      de,n_b1
        call    d_streq
        jp      nz,t_fail
        ld      ix,fib1
        d_fn    _FNEXT
        d_ok
        ld      hl,fib1+1
        ld      de,n_a2
        call    d_streq
        jp      nz,t_fail
        ld      ix,fib2
        d_fn    _FNEXT
        d_err   D_NOFIL
        ld      ix,fib1
        d_fn    _FNEXT
        d_err   D_NOFIL
        d_step  7                       ; from a FIB naming T; the whole path
        ld      de,s_t
        ld      b,10h
        ld      ix,fib1
        d_fn    _FFIRST
        d_ok
        ld      a,(fib1+14)
        and     10h
        jp      z,t_fail
        ld      de,fib1
        ld      hl,n_a1
        ld      b,0
        ld      ix,fib2
        d_fn    _FFIRST
        d_ok
        ld      hl,fib2+1
        ld      de,n_a1
        call    d_streq
        jp      nz,t_fail
        ld      de,buf
        d_fn    _WPATH
        d_ok
        push    hl
        ld      hl,buf
        ld      de,s_wp
        call    d_streq
        pop     hl
        jp      nz,t_fail
        ld      de,n_a1
        call    d_streq
        jp      nz,t_fail
        d_step  8                       ; a new entry from a template
        ld      hl,n_x9
        ld      de,fib1+1
        ld      bc,7
        ldir
        ld      de,s_tnq
        ld      b,0
        ld      ix,fib1
        d_fn    _FNEW
        d_ok
        ld      hl,fib1+1
        ld      de,n_n9
        call    d_streq
        jp      nz,t_fail
        ld      de,fib1
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        d_step  9                       ; create new on what exists
        ld      de,s_a1
        ld      b,80h
        ld      ix,fib1
        d_fn    _FNEW
        d_err   D_FILEX
        d_step  10                      ; a FIB to delete, then not found
        ld      de,s_a1
        ld      b,0
        ld      ix,fib1
        d_fn    _FFIRST
        d_ok
        ld      de,fib1
        d_fn    _DELETE
        d_ok
        ld      de,s_a1
        ld      b,0
        ld      ix,fib1
        d_fn    _FFIRST
        d_err   D_NOFIL
        d_step  11                      ; no match; no directory
        ld      de,s_tnope
        ld      b,0
        ld      ix,fib1
        d_fn    _FFIRST
        d_err   D_NOFIL
        ld      de,s_nopeall
        ld      b,0
        ld      ix,fib1
        d_fn    _FFIRST
        d_err   D_NODIR
        jp      t_ok

; mk — DE -> a path, B = attributes: made; a file is closed. mkf — a
; file.
mkf:    push    bc
        push    de
        xor     a
        d_fn    _CREATE
        d_ok
        d_fn    _CLOSE
        d_ok
        pop     de
        pop     bc
        ret
mk:     xor     a
        d_fn    _CREATE
        d_ok
        ret
; count — DE -> a pattern, B = attributes: A = the entries found, each
; with FFh first and the drive 1.
count:  ld      ix,fib1
        d_fn    _FFIRST
        ld      c,0
.loop:  or      a
        jr      nz,.end
        ld      a,(fib1)
        inc     a
        jp      nz,t_fail
        ld      a,(fib1+25)
        dec     a
        jp      nz,t_fail
        inc     c
        push    bc
        ld      ix,fib1
        d_fn    _FNEXT
        pop     bc
        jr      .loop
.end:   d_err   D_NOFIL
        ld      a,c
        ret

        d_lib   "hfind"
s_t:    db      'F',0
s_a1:   db      'F\A1.TXT',0
s_a2:   db      'F\A2.TXT',0
s_b1:   db      'F\B1.DAT',0
s_sub:  db      'F\SUB',0
s_h:    db      'F\H.TXT',0
s_tall: db      'F\*.*',0
s_taq:  db      'F\A?.TXT',0
s_tastar: db    'F\A*.*',0
s_tbstar: db    'F\B*.*',0
s_tnq:  db      'F\N?.TXT',0
s_tnope: db     'F\NOPE*',0
s_nopeall: db   'NOPE\*.*',0
s_wp:   db      'F\A1.TXT',0
n_a1:   db      'A1.TXT',0
n_a2:   db      'A2.TXT',0
n_b1:   db      'B1.DAT',0
n_x9:   db      'X9.TXT',0
n_n9:   db      'N9.TXT',0
fib1:   ds      64
fib2:   ds      64
buf:    ds      64
