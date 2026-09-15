; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; M6.COM — the product: started under Nextor, it takes the machine and
; boots the kernel, which then runs /etc/rc and a shell. Steps: SCREEN 0
; at 80 columns; a Nextor 2 kernel, or a refusal; the driver behind the
; current drive; the capture; mem=<K> from the command line; the
; takeover, with the resident and the switched part carried in this
; file. A failure prints its code and returns to DOS.
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "version.inc"

NB_TERM     equ 62h

        org     100h
start:
        ld      sp,KT_LSTACK            ; page 2: the DOS stack dies in the
                                        ; takeover
        call    ld_screen80
        ld      de,s_banner
        call    nb_puts
        call    ld_nextor2
        jr      z,.nextor2
        ld      de,s_nextor
        call    nb_puts
        jp      fail
.nextor2:
        call    nb_find
        or      a
        jp      nz,fail
        call    nb_capture
        or      a
        jp      nz,fail
        call    nb_mem
        jp      c,fail
        ld      de,s_drive
        call    nb_puts
        ld      a,(nb_drive)
        add     a,'A'
        call    nb_putc
        ld      de,s_wall
        call    nb_puts
        ld      hl,(REC+KR_WALL)
        call    nb_puthex16
        ld      de,s_drivers
        call    nb_puts
        ld      a,(REC+KR_NDRV)
        call    nb_putdec
        call    nb_newline
        ld      hl,0
        ld      (REC+KR_TEST),hl        ; no test program: init runs
        ld      hl,ksimage
        ld      (REC+KR_KSEG_SRC),hl
        ld      hl,ksimage_end-ksimage
        ld      (REC+KR_KSEG_LEN),hl
        call    ld_takeover
        jp      fail                    ; it returns only with A = F3h

; fail — A = the code: printed, and back to DOS.
fail:
        push    af
        ld      de,s_fail
        call    nb_puts
        pop     af
        call    nb_puthex8
        call    nb_newline
        ld      b,1
        ld      c,NB_TERM
        jp      BDOS

s_banner:   db  "m6 ",M6_VERSION,13,10,'$'
s_nextor:   db  "m6 needs a Nextor 2 kernel",13,10,'$'
s_drive:    db  "drive $"
s_wall:     db  ", wall $"
s_drivers:  db  "h, drivers $"
s_fail:     db  "m6: boot failed, code $"
REC:        ds  KREC_SIZE

nb_rec      equ REC
nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"
        include "nextor/capture.asm"
        include "loader/nxboot.asm"

ld_image    equ kimage
ld_rec      equ REC
ld_block    equ 0
ld_block_len equ 0
        include "loader/takeover.asm"

; The images, read while page 1 may be switched away by a driver call:
; the code above stays in page 0, the images below it may extend into
; page 1 and never into page 2, where the loader's stack and scratch are.
        ASSERT  $ < 4000h
kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
        ASSERT  ksimage_end < 8000h
