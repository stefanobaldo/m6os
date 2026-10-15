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
;
; Turbo (docs/block-device.md): a cartridge that is itself the machine's
; memory mapper may add the m6 block device's registers at BD_BASE of
; bank 7, beside the SD Mapper's own; the port looks for their signature
; at init and answers the ROM's boot's probe from them, and when the
; kernel puts the device in Turbo (DQ_MODE), a call hands the device
; (device, sector, count, target segment and slot) and polls its status
; by the tick while it moves the sectors itself — the CPU copies
; nothing. The probe byte written at the target first lets the device
; refuse a target that is not in its RAM, on which the call falls back
; to the SPI window. A cartridge without the block reads the ROM's fill
; there (FFh), and the port runs Standard as before.

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
        db      DF_TURBO                ; DRV_FLAGS
        jp      sd_init                 ; DRV_INIT
        jp      sd_info                 ; DRV_INFO
        jp      sd_status               ; DRV_STATUS
        jp      sd_rw                   ; DRV_RW
        jp      sd_query                ; DRV_QUERY
        jp      sdp_probe               ; DRV_PROBE
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

; sdp_bd_detect — A = the block device's BD_CAPS when its signature and
; version are at BD_BASE, else 0. The core calls it at init; the probe
; below before there is a kernel. No RAM, no tick. Corrupts B, DE, HL.
sdp_bd_detect:
        ld      hl,BD_SIGN
        ld      de,sdp_s_m6bd
        ld      b,4
.sign:  ld      a,(de)
        cp      (hl)
        jr      nz,.none
        inc     hl
        inc     de
        djnz    .sign
        ld      a,(BD_VER)
        cp      BD_VER_1
        jr      nz,.none
        ld      a,(BD_CAPS)
        ret
.none:  xor     a
        ret

; sdp_probe — DRV_PROBE: A = the subslot of the cartridge's slot holding
; the device's mapper, CF clear, when the block offers Turbo and serves a
; mapper; else CF set, A = E_NOSYS. Called by the kernel ROM's boot
; before init, with nothing of the kernel in place.
sdp_probe:
        call    sdp_bd_detect
        and     BDC_TURBO|BDC_MAPPER
        cp      BDC_TURBO|BDC_MAPPER
        jr      nz,.no
        ld      a,(BD_CAPS)
        and     BDC_MSUB
        rrca
        rrca
        rrca
        rrca
        ret
.no:    ld      a,E_NOSYS
        scf
        ret

; sdp_turbo — the call through the block device: IX the record, IY the
; slot's record, SD_CARD, SD_N, SD_TGT and SD_WR set, DE:HL the sector,
; the sense read and the refusals done. The device gets the device, the
; sector, the count, the target as segment (API2_DRV_TGTSEG) and slot,
; the probe byte — a read: the byte at the target complemented and
; written back; a write: the target's first byte — and the command; the
; status is polled by the tick, and before anything is written a command
; still running is waited out under the same bound. Out: CF clear, A = 0, B = 0 when the
; sectors moved; CF set and A = 0 when the device refused the probe (the
; call goes on through the window: DE, HL preserved); CF set, A = the
; errno and B = 40h | the device's code otherwise. Corrupts BC.
SD_TO_TURBO     equ 255         ; 4.25 s: the device ends a command in 4
sdp_turbo:
        push    hl
        push    de
        call    sd_t0
.idle:  ld      a,(BD_STAT)             ; no register written while the
        cp      BDS_BUSY                ; device is busy
        jr      nz,.free
        ld      b,SD_TO_TURBO
        call    sd_elapsed
        jr      c,.idle
        jr      .tmo
.free:  pop     de
        pop     hl
        push    hl
        push    de
        ld      (BD_LBA),hl
        ld      (BD_LBA+2),de
        ld      a,(ix+SD_CARD)
        ld      (BD_DEV),a
        ld      a,(ix+SD_N)
        ld      (BD_COUNT),a
        k_call2 API2_DRV_TGTSEG
        ld      (BD_SEG),a
        ld      a,(ix+SD_TGT)
        and     3Fh                     ; 80h + the slot: the slot alone
        ld      (BD_SLOT),a
        ld      h,(ix+SD_TGT)
        ld      l,0
        ld      a,(hl)
        bit     0,(ix+SD_WR)
        jr      nz,.probe               ; a write: the first byte as it is
        cpl                             ; a read: a byte that is not there
        ld      (hl),a
.probe: ld      (BD_PROBE),a
        ld      a,BDO_READ
        bit     0,(ix+SD_WR)
        jr      z,.cmd
        ld      a,BDO_WRITE
.cmd:   ld      (BD_CMD),a
        call    sd_t0
.poll:  ld      a,(BD_STAT)
        cp      BDS_BUSY
        jr      nz,.done
        ld      b,SD_TO_TURBO
        call    sd_elapsed
        jr      c,.poll
.tmo:   ld      b,SD_ETIMEOUT
        ld      a,E_IO
        jr      .err
.done:  or      a
        jr      z,.ok
        cp      BDE_PROBE
        jr      z,.window
        ld      b,a
        set     6,b                     ; 40h | the device's code
        cp      BDE_NOMEDIUM
        ld      a,E_NXIO
        jr      z,.err
        ld      a,b
        cp      40h|BDE_RO
        ld      a,E_ROFS
        jr      z,.err
        ld      a,E_IO
.err:   scf
        jr      .out
.window:
        xor     a                       ; A = 0 with CF set: the window
        scf
        jr      .out
.ok:    xor     a
        ld      b,a
.out:   pop     de
        pop     hl
        ret

sdp_s_m6bd:
        db      "M6BD"
sdp_s_slot:
        db      "SD slot n                       "
        ASSERT  $-sdp_s_slot == 32
sdp_s_sdhc:
        db      "SDHC"
sdp_s_sdsc:
        db      "SDSC"
        ASSERT  $ <= SDP_WIN            ; the window replaces the ROM
                                        ; from here while a card is on
