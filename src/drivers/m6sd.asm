; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; m6sd — the SD Mapper driver: a block written to m6's contract
; (docs/drivers.md) for the FBLabs SD Mapper V2 and the cartridges that
; present its register set (the MSX-Pico+), for the driver bank of the
; ASCII16 kernel ROM. The two card slots are devices 1 and 2. This file
; is the port — the cartridge's registers and the eight things the SD
; protocol core needs of them — and src/drivers/sdspi.asm, included
; below, is everything else: the protocol, the entries, the record.
;
; The cartridge, in bank 7 of its ROM: the SPI window at 7B00h-7EFFh,
; where every read exchanges FFh for the byte the card sends and every
; write sends the byte written, the CPLD holding WAIT for the eight
; bits — one bus cycle per byte, ~21 T under LDI on silicon — and the
; same 1 024 bytes are the window wherever LDI's pointer walks through
; them; 7FF0h, written, selects card 1 (bit 0) or card 2 (bit 1), and
; read with a card selected gives its write-protect switch (bit 2),
; its absence (bit 1) and a latch set while it was absent (bit 0),
; cleared by that read. Nothing here writes a slot or mapper register,
; nothing disables interrupts: the handler never touches page 1, and a
; card waits as long as the bus does between two bytes. The bank's
; bytes from 7B00h are the window while a card is selected, so the
; block ends below that address (the assertion at the end). Included
; at DRV_BASE of the ROM's bank 7 by src/rom/rom.asm, which has
; kernel.inc in already. Variables: SD_RAM bytes of page 3, IX on every
; entry.

SDP_WIN         equ 7B00h       ; the SPI window
SDP_SENSE       equ 7FF0h       ; card select (write), sense (read)

        macro   sdp_out                 ; A sent
        ld      (SDP_WIN),a
        endm
        macro   sdp_in                  ; FFh sent, the byte received in A
        ld      a,(SDP_WIN)
        endm
        macro   sdp_in512               ; 512 bytes into DE
        call    sdp_copy_in
        endm
        macro   sdp_out512              ; 512 bytes from HL
        call    sdp_copy_out
        endm
        macro   sdp_select              ; A = 1 or 2
        ld      (SDP_SENSE),a
        endm
        macro   sdp_deselect
        xor     a
        ld      (SDP_SENSE),a
        endm

        db      "M6DRV"                 ; DRV_SIGN
        db      DRV_VER_1               ; DRV_VER
        db      0                       ; DRV_FLAGS
        jp      sd_init                 ; DRV_INIT
        jp      sd_info                 ; DRV_INFO
        jp      sd_status               ; DRV_STATUS
        jp      sd_rw                   ; DRV_RW
        jp      sd_query                ; DRV_QUERY
        jp      sd_nosys                ; DRV_RES1
        jp      sd_nosys                ; DRV_RES2
        dw      SD_RAM                  ; DRV_RAM
        dw      0                       ; DRV_RELOC
        db      "m6sd            "      ; DRV_NAME
        ASSERT  $-DRV_BASE == DRV_HDR

        include "sdspi.asm"

; sdp_copy_in — 512 bytes from the window to DE; sdp_copy_out — 512
; bytes from HL to the window: one LDI a byte, the copy the bench
; measured in the cartridge's own driver, the pointer into the window
; walking its 1 024 bytes. Called once a sector. Corrupt BC, and HL or
; DE respectively.
sdp_copy_in:
        ld      hl,SDP_WIN
        jr      sdp_copy
sdp_copy_out:
        ld      de,SDP_WIN
sdp_copy:
        DUP     512
        ldi
        EDUP
        ret

sdp_s_slot:
        db      "SD slot n                       "
        ASSERT  $-sdp_s_slot == 32
sdp_s_sdhc:
        db      "SDHC"
sdp_s_sdsc:
        db      "SDSC"
        ASSERT  $ <= SDP_WIN            ; the window replaces the ROM
                                        ; from here while a card is on
