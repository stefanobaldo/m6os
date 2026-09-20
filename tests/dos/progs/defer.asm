; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; defer — the program's disk error routine, kept in page 2 with its
; counter beside it: the page the system takes for its own code while it
; serves a file function. The harness makes the next crossing of an
; _OPEN fail with a disk error, twice, after each line this prints and
; the key it waits for. The routine must be reached — so the program's
; page 2 is back when it is called — may call the system from inside,
; and answers 3 the first time, which hands the error to the caller, and
; 2 the second, which has the call made again and succeed.
        include "dos/progs/dos.inc"
_OPEN           equ 43h
_CLOSE          equ 45h
_CURDRV         equ 19h
_DEFER          equ 64h
ROUTINE         equ 8100h       ; where the routine goes
COUNT           equ 8180h       ; and its counter
        org     100h
        xor     a
        ld      (0C000h),a              ; not the kernel's page 3 (the
        ld      (0C001h),a              ; harness tells the two apart)
        ld      (COUNT),a
        ld      hl,routine
        ld      de,ROUTINE
        ld      bc,routine_end-routine
        ldir
        ld      de,ROUTINE
        ld      c,_DEFER
        call    BDOS
        d_puts  s_armed1
        ld      c,_CONIN
        call    BDOS
        ld      de,s_file
        xor     a
        ld      c,_OPEN
        call    BDOS
        or      a                       ; handed back: the open fails (with
        jr      z,fail                  ; the code the failing step gives)
        ld      a,(COUNT)
        cp      1
        jr      nz,fail
        d_puts  s_armed2
        ld      c,_CONIN
        call    BDOS
        ld      de,s_file
        xor     a
        ld      c,_OPEN
        call    BDOS
        or      a                       ; made again, and well
        jr      nz,fail
        ld      c,_CLOSE
        call    BDOS
        ld      a,(COUNT)
        cp      2
        jr      nz,fail
        d_puts  s_ok
        ld      c,_TERM0
        call    BDOS
fail:   d_puts  s_fail
        ld      b,1
        ld      c,_TERM
        call    BDOS

; The routine, assembled for ROUTINE: counts, calls the system, answers.
routine:
        DISP    ROUTINE
        ld      hl,COUNT
        inc     (hl)
        ld      c,_CURDRV
        call    BDOS
        ld      a,(COUNT)
        cp      1
        ld      a,3
        ret     z
        ld      a,2
        ret
        ENT
routine_end:
s_file:   db    '\DOS\HELLO.COM',0
s_armed1: db    13,10,"defer: one, press a key$"
s_armed2: db    13,10,"defer: two, press a key$"
s_ok:     db    13,10,"defer ok",13,10,"$"
s_fail:   db    13,10,"defer fail",13,10,"$"
