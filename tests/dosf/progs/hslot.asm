; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hslot — a program that moves its slots about. With another slot in
; page 2 — slot 0, where an MSX2 has no RAM — a routine of the program's
; own in the RAM of page 2 is called through CALSLT, and changes IY as a
; BIOS routine may: the slot that was in page 2 must be there again
; afterwards. Then the RAM goes back, by ENASLT.
        include "dosf/progs/dosf.inc"
CALSLT          equ 001Ch
ENASLT          equ 0024h
RAMAD2          equ 0F343h      ; the RAM's slot in page 2
ROUTINE         equ 8100h
        org     100h
        ld      hl,routine
        ld      de,ROUTINE
        ld      bc,routine_end-routine
        ldir
        d_step  1                       ; slot 0 into page 2
        xor     a
        ld      h,80h
        call    ENASLT
        ei
        call    page2
        or      a
        jp      nz,restore_fail
        d_step  2                       ; the routine, in the RAM's page 2
        ld      a,(RAMAD2)
        ld      iyh,a
        ld      ix,ROUTINE
        ld      a,5
        call    CALSLT
        ei
        cp      6                       ; it ran, and answered
        jp      nz,restore_fail
        call    page2                   ; and slot 0 is back in page 2
        or      a
        jp      nz,restore_fail
        call    restore
        jp      t_ok

; page2 — A = page 2's primary slot, from the register.
page2:  in      a,(0A8h)
        rrca
        rrca
        rrca
        rrca
        and     3
        ret
; restore — the RAM back in page 2.
restore:
        ld      a,(RAMAD2)
        ld      h,80h
        call    ENASLT
        ei
        ret
restore_fail:
        push    af
        call    restore
        pop     af
        jp      t_fail

; The routine, assembled for ROUTINE: A + 1, and IY changed.
routine:
        DISP    ROUTINE
        inc     a
        ld      iy,0
        ret
        ENT
routine_end:

        d_lib   "hslot"
