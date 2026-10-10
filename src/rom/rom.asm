; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The kernel ROM: m6 in the cartridge, booting with no system file on the
; card. 128K, eight banks of 16K switched by the cartridge's mapper
; through CHGBNK at 7FD0h, which every bank carries — copied at build time
; from the driver's bank, never written here, so one source serves every
; cartridge type: the build names the Nextor kernel ROM built for that
; cartridge (NEXTOR_ROM, the Sunrise IDE's by default) and takes from it
; the bank switch and the driver bank. Bank 0 is an
; MSX cartridge whose page 0 (4000h-40FFh) is what a Nextor 2 driver sees
; of the kernel it was written for — GSLOT1, RDBANK, CALBNK, GWORK, K_SIZE
; and CUR_BANK at their addresses, CALBNK's body byte for byte — followed
; by the boot routine and the resident image. Banks 1 and 2 carry the
; switched and the boot images; banks 3 to 6 are empty; bank 7 is the
; driver: bank 7 of the Nextor kernel ROM built for that cartridge,
; whole. Every bank begins with the cartridge header and the
; INIT trampoline, because the mapper register has no reset state the ROM
; may count on; the driver bank's own INIT, Nextor's, lands at ROM_NXINIT
; in bank 0, where a jump waits for it.
;
; Boot: at the slot scan, INIT hooks H.RUNC and returns. When the BIOS runs
; that hook every INIT has run, the BIOS is in page 0, RAM in pages 2 and
; 3, and the hook's inter-slot call has put this slot in page 1; the boot
; routine (boot.asm beside this file) relocates itself to page 2,
; initialises the driver, fills the takeover record, copies the three
; images from the banks into the mapper's segments, gives page 1 to RAM
; and takes the machine over as M6.COM does. Nothing of Nextor runs, and
; the kernel does not know it booted from a ROM.
;
; The build passes the Nextor kernel ROM's directory on the include path,
; where incbin finds it, and its name as NEXTOR_ROM when it is not the
; default; tools/check-rom.sh then compares the bytes this file must
; reproduce with the driver bank's and fails the build when they differ.
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"      ; K_IMAGE_ROOF: the roof the wall
                                        ; must stay above (boot.asm)
        include "version.inc"

        ; Each bank is its own ORG 4000h; the output is sequential and the
        ; assembler's note that ORG went backwards says nothing here.
        OPT     -Wno-fileorg
        IFNDEF  NEXTOR_ROM
        DEFINE  NEXTOR_ROM "Nextor-2.1.4.SunriseIDE.ROM"
        ENDIF
ROM_BANK        equ 4000h       ; a bank
ROM_TRAMP       equ 4010h       ; the INIT trampoline, after the header
ROM_HEAD        equ 4018h       ; where a bank's payload begins
ROM_DRVBANK     equ 7           ; the driver's bank, K_SIZE's value
ROM_KSEG_BANK   equ 1           ; the switched image's bank
ROM_KBOOT_BANK  equ 2           ; the boot image's bank
ROM_TAIL        equ 8000h-NX_CHGBNK    ; CHGBNK and what follows it, 30h
ROM_NXINIT      equ 47D6h       ; where the driver bank's INIT trampoline
                                ; (Nextor's: xor a / call CHGBNK / jp)
                                ; lands once bank 0 is in; check-rom.sh
                                ; reads the target from the driver bank

; Every bank: the 16-byte header, then the trampoline — switch to bank 0,
; where INIT is — at the same address in every bank, so that whichever
; bank the BIOS scans, it runs the same bytes.
        MACRO   rom_head
        ORG     4000h
        db      "AB"
        dw      ROM_TRAMP               ; INIT
        dw      0,0,0                   ; STATEMENT, DEVICE, TEXT
        ds      6,0
        ASSERT  $ = ROM_TRAMP
        xor     a
        call    NX_CHGBNK
        jp      rom_init0
        ds      ROM_HEAD-$,0
        ENDM
; Every bank's end: FFh to CHGBNK, then CHGBNK from the driver's bank.
        MACRO   rom_tail
        ASSERT  $ <= NX_CHGBNK
        ds      NX_CHGBNK-$,0FFh
        incbin  NEXTOR_ROM, ROM_DRVBANK*ROM_BANK+(NX_CHGBNK-4000h), ROM_TAIL
        ASSERT  $ = 8000h
        ENDM

; ---------------------------------------------------------------- bank 0
        rom_head
        ; The page a driver calls into. Addresses from nextor.inc; the
        ; routines after GWORK's jump fill the gap to CALBNK's body.
        ds      NX_GSLOT1-$,0
        jp      rom_gslt1               ; 402Dh GSLOT1
        ds      NX_RDBANK-$,0
        ld      a,(hl)                  ; 403Ch RDBANK, in place
        ret
        ds      NX_CALLB0-$,0
        ret                             ; 403Fh CALLB0: not served
        ds      NX_CALBNK-$,0
        jp      NX_CALBNK_BODY          ; 4042h CALBNK
        ASSERT  $ = NX_GWORK
        jp      rom_gwork               ; 4045h GWORK

; rom_gslt1 — A = the slot of page 1, E000SSPP, from the PPI and SLTTBL.
; Preserves BC, DE, HL.
rom_gslt1:
        push    hl
        push    bc
        in      a,(PPI_A)
        rrca
        rrca
        and     3
        ld      c,a
        ld      b,0
        ld      hl,B_EXPTBL
        add     hl,bc
        bit     7,(hl)
        jr      z,.plain
        ld      hl,B_SLTTBL
        add     hl,bc
        ld      a,(hl)
        and     0Ch                     ; page 1's subslot, bits 3-2
        or      c
        or      80h
        ld      c,a
.plain: ld      a,c
        pop     bc
        pop     hl
        ret

; rom_gwork — Nextor's GWRK: A = slot, or 0 for page 1's; IX = that slot's
; 8-byte SLTWRK entry, SLTWRK + primary*32 + subslot*8. A = the slot;
; corrupts F only. The driver calls it through CALBNK on every DEV_RW.
rom_gwork:
        or      a
        jr      nz,.have
        call    rom_gslt1
.have:  push    af
        push    bc
        ld      b,a
        rrca
        rrca
        rrca
        and     60h                     ; primary * 32
        ld      c,a
        ld      a,b
        rlca
        and     18h                     ; subslot * 8
        or      c
        ld      c,a
        ld      b,0
        ld      ix,B_SLTWRK
        add     ix,bc
        pop     bc
        pop     af
        ret

        ASSERT  $ <= NX_CALBNK_BODY
        ds      NX_CALBNK_BODY-$,0
        ; CALBNK's body, Nextor's byte for byte (bank0/doshead.mac): the
        ; caller's bank saved, the return address 40DDh pushed, the
        ; routine's address under it, the target bank switched in — and
        ; from there the bytes run in the target bank: the ret into the
        ; routine, then at 40DDh the way back to the caller's bank. The
        ; build compares 40DBh-40E1h with the driver bank's.
        exx
        ld      e,a
        ld      a,(NX_CUR_BANK)
        push    af
        ld      bc,40DDh
        push    bc
        push    ix
        push    hl
        pop     ix
        ld      a,e
        exx
        call    NX_CHGBNK
        ex      af,af'                  ; 40DBh: in the target bank
        ret
        ex      af,af'                  ; 40DDh: back from the routine
        pop     af
        call    NX_CHGBNK
        ex      af,af'                  ; in the caller's bank again
        ret
        ASSERT  $ = 40E4h
        ds      NX_K_SIZE-$,0
        db      ROM_DRVBANK             ; 40FEh K_SIZE: the driver's bank
        db      0                       ; 40FFh CUR_BANK
        ASSERT  $ = 4100h

        include "rom/boot.asm"

        ASSERT  $ <= ROM_NXINIT
        ds      ROM_NXINIT-$,0FFh
        jp      rom_init0               ; the driver bank's INIT lands here
rom_resident:
        incbin  "build/kernel.bin"
rom_resident_end:
ROM_B0_FREE     equ NX_CHGBNK-$
        EXPORT  ROM_B0_FREE
        rom_tail

; ---------------------------------------------------------------- bank 1
        rom_head
rom_kseg:
        incbin  "build/kseg.bin"
rom_kseg_end:
        ASSERT  rom_kseg_end-rom_kseg <= 4000h
ROM_B1_FREE     equ NX_CHGBNK-$
        EXPORT  ROM_B1_FREE
        rom_tail

; ---------------------------------------------------------------- bank 2
        rom_head
rom_kboot:
        incbin  "build/kboot.bin"
rom_kboot_end:
        ASSERT  rom_kboot_end-rom_kboot <= KB_MAX
ROM_B2_FREE     equ NX_CHGBNK-$
        EXPORT  ROM_B2_FREE
        rom_tail

; ----------------------------------------------------------- banks 3 to 6
        DUP     4
        rom_head
        rom_tail
        EDUP

; ---------------------------------------------------------------- bank 7
        ORG     4000h
        incbin  NEXTOR_ROM, ROM_DRVBANK*ROM_BANK, ROM_BANK
        ASSERT  $ = 8000h
