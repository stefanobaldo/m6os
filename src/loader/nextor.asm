; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; NEXTOR.SYS — the product, loaded by the Nextor kernel ROM in place of
; Nextor's own system file: the kernel opens \NEXTOR.SYS on the boot
; drive, reads its first NX_SYS_FIRST bytes to 0100h and jumps here, with
; its own BDOS live at F37Dh and nothing at 0005h, its ROM in page 1, RAM
; in pages 0 and 2, interrupts on and an empty command line. Steps: ESC
; held means Nextor instead (below); SCREEN 0 at 80 columns; a Nextor 2
; kernel, or a refusal; the driver behind the current drive; the capture;
; the rest of this file read into page 1; the takeover, with the
; resident, the switched part and the boot image carried in this file.
; No arguments: mem= is M6.COM's. A failure prints its code and loads
; Nextor.
;
; Nextor is the card's original NEXTOR.SYS kept as \MSXDOS2.SYS — the
; name the kernel itself falls back to when NEXTOR.SYS is missing, and
; the one CALL SYSTEM2 boots from Disk BASIC. With ESC down when this
; starts, or after a failure, a stub in page 2 reads that file over this
; one and jumps to it, as the kernel would have; if that file cannot be
; read either, Disk BASIC through the kernel ROM's 4022h entry.
        DEFINE  NX_BDOS_KERNEL  ; BDOS is the kernel's F37Dh: nothing at 0005h
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "version.inc"

NB_OPEN     equ 43h
NB_CLOSE    equ 45h
NB_READ     equ 48h
NB_SEEK     equ 4Ah
NB_RDONLY   equ 1               ; _OPEN mode: no write
NB_BASIC    equ 4022h           ; the kernel ROM: Disk BASIC
NB_TAIL     equ 100h+NX_SYS_FIRST   ; where the kernel's read stopped

        org     100h
start:
        ld      hl,(B_JIFFY)            ; the boot's clock, before anything
        ld      (REC+KR_JIFFY),hl
        ld      (nb_sp),sp              ; the kernel's stack, for the stub
        ld      sp,KT_LSTACK            ; page 2: the kernel's stack dies
                                        ; in the takeover
        ; ESC held: Nextor. Row 7 of the matrix, bit 2, read with
        ; interrupts off because the BIOS's tick rewrites the row select.
        di
        in      a,(PPI_C)
        and     0F0h
        or      7
        out     (PPI_C),a
        in      a,(PPI_B)
        ei
        bit     2,a
        jp      z,chain
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
        call    ld_tail
        jp      nz,fail
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
        ld      hl,kbimage
        ld      (REC+KR_BOOT_SRC),hl
        ld      hl,kbimage_end-kbimage
        ld      (REC+KR_BOOT_LEN),hl
        call    ld_takeover
        jp      fail                    ; it returns only with A = F3h

; ld_tail — the rest of this file, from NX_SYS_FIRST, into page 1, where
; the kernel's read stopped. Page 1 gets its RAM first; the kernel moves
; the data through its own buffer while its ROM is there. Out: Z with the
; images in place, or A = F7h, NZ: the file could not be opened or read,
; or is not whole. Corrupts everything.
ld_tail:
        ld      a,(RAMAD1)
        ld      h,40h
        call    ENASLT
        ei
        ld      de,s_self
        ld      a,NB_RDONLY
        ld      c,NB_OPEN
        call    BDOS
        or      a
        jr      nz,.bad
        ld      a,b
        ld      (nb_fh),a
        xor     a                       ; from the start
        ld      de,0
        ld      hl,NX_SYS_FIRST
        ld      c,NB_SEEK
        call    BDOS
        or      a
        jr      nz,.bad
        ld      a,(nb_fh)
        ld      b,a
        ld      de,NB_TAIL
        ld      hl,4000h                ; as much as there is
        ld      c,NB_READ
        call    BDOS
        or      a
        jr      nz,.bad
        ld      de,kbimage_end-NB_TAIL
        or      a
        sbc     hl,de                   ; HL = what was read
        jr      nz,.bad
        ld      a,(nb_fh)
        ld      b,a
        ld      c,NB_CLOSE
        call    BDOS
        or      a
        ret     z
.bad:   ld      a,0F7h
        or      a
        ret

; fail — A = the code: printed, then Nextor.
fail:
        push    af
        ld      de,s_fail
        call    nb_puts
        pop     af
        call    nb_puthex8
        call    nb_newline
; chain — Nextor. The stub runs from page 2 because the read lands on
; this code; it carries the stack the kernel had and puts it back, and
; leaves 0080h as the kernel wrote it.
chain:
        ld      de,s_chain
        call    nb_puts
        ld      hl,stub
        ld      de,KT_CHAIN
        ld      bc,stub_end-stub
        ldir
        ld      hl,(nb_sp)
        ld      (st_sp),hl              ; into the copy
        jp      KT_CHAIN
stub:
        DISP    KT_CHAIN
        ld      de,s_msxdos2
        ld      a,NB_RDONLY
        ld      c,NB_OPEN
        call    BDOS
        or      a
        jr      nz,.basic
        ld      a,b
        ld      (st_fh),a
        ld      de,100h
        ld      hl,NX_SYS_FIRST
        ld      c,NB_READ
        call    BDOS
        or      a
        jr      nz,.basic
        ld      a,(st_fh)
        ld      b,a
        ld      c,NB_CLOSE
        call    BDOS
        or      a
        jr      nz,.basic
        ld      sp,(st_sp)
        jp      100h
.basic: jp      NB_BASIC
st_fh:  db      0
st_sp:  dw      0
s_msxdos2: db   '\MSXDOS2.SYS',0
        ENT
stub_end:
        ASSERT  stub_end-stub <= 128

s_banner:   db  "m6 ",M6_VERSION,13,10,'$'
s_nextor:   db  "m6 needs a Nextor 2 kernel",13,10,'$'
s_drive:    db  "drive $"
s_wall:     db  ", wall $"
s_drivers:  db  "h, drivers $"
s_fail:     db  "m6: boot failed, code $"
s_chain:    db  "m6: loading Nextor",13,10,'$'
s_self:     db  '\NEXTOR.SYS',0
nb_sp:      dw  0
nb_fh:      db  0
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
; The kernel reads the file up to NB_TAIL and ld_tail the rest, so the
; file must reach past that point and end in page 1. The boot image is
; copied from here to KB_BASE in page 0 by the kernel, over the two
; images' dead sources.
        ASSERT  $ < 4000h
kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
kbimage:
        incbin  "build/kboot.bin"
kbimage_end:
        ASSERT  kbimage_end > NB_TAIL
        ASSERT  kbimage_end < 8000h
