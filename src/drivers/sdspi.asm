; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; sdspi — the SD card protocol in SPI mode, written from the SD Physical
; Layer specification, as the core of a driver block to m6's contract
; (docs/drivers.md): what every SD cartridge's driver does, with nothing
; of the cartridge in it. A port includes this file after it has defined
; the two equates and the six macros below, and the entries here are the
; block's — init, info, status, rw, query — against a record of SD_SLOT
; bytes per card slot in the block's RAM, IX at every entry.
;
;   SDP_WIN      an address whose read exchanges FFh and returns the byte
;                received, whose write sends the byte written
;   SDP_SENSE    an address read with a card selected: SDP_B_CHANGED,
;                SDP_B_ABSENT, SDP_B_PROT the bits
;   sdp_out      sends A; sdp_in: sends FFh, the byte received in A
;   sdp_in512    512 bytes received into DE, DE advanced; corrupts HL, BC
;   sdp_out512   512 bytes sent from HL, HL advanced; corrupts DE, BC
;   sdp_select   A = 1 or 2: that card's CS asserted, the other's off
;   sdp_deselect every CS off; corrupts A
;
; Init brings each slot up at whatever clock the port has — the SD
; Mapper's CPLD has one, 12.5 MHz — with CMD0, CMD8, ACMD41 (HCS when the
; card is version 2), CMD58 for the capacity class, CMD16 on a
; standard-capacity card, then the CSD for the sector count and the CID
; for the listing's name; a slot whose sense says absent is skipped
; before any traffic, and a card that fails a step is a slot with no
; medium, the step kept in its record. A call of B sectors is one
; CMD18 ended by CMD12, or one ACMD23 + CMD25 ended by the stop token;
; one sector is CMD17 or CMD24. Every response is read within eight
; bytes, every token and busy by the kernel's tick with the
; specification's bounds rounded up to whole ticks; nothing disables
; interrupts. The sense register is read at the top of every rw and
; status, and the latch it carries is kept in the record: a slot whose
; card changed answers E_NXIO until status re-initialises it, a
; protected card refuses writes with E_ROFS before any traffic.

; The record of a slot, SD_SLOT bytes; slot n (1 or 2) is record n - 1.
SD_STATE        equ 0           ; 0 no medium, 1 SDSC, 2 SDHC/SDXC
SD_FLAGS        equ 1           ; SDF_*: the sense bits as kept, and bit 7
SD_CODE         equ 2           ; the init step that failed, SD_E*, or 0
SD_TOTAL        equ 4           ; 4: sectors
SD_CID          equ 8           ; 16: the CID as read
SD_SLOT         equ 24
SDF_CHANGED     equ 1           ; bit 0: the card changed since init
SDF_ABSENT      equ 2           ; bit 1: no card in the slot
SDF_PROT        equ 4           ; bit 2: the write-protect switch
SDF_FAILED      equ 80h         ; bit 7: a card is there and init failed
; The call's variables after the two records.
SD_T0           equ 2*SD_SLOT   ; 2: the tick at the current wait's entry
SD_CARD         equ SD_T0+2     ; the call's slot, 1 or 2
SD_N            equ SD_T0+3     ; sectors left in the call
SD_TGT          equ SD_T0+4     ; the high byte of the sector's target
SD_WR           equ SD_T0+5     ; 1 = a write
SD_V2           equ SD_T0+6     ; init: the card answered CMD8
SD_RAM          equ SD_T0+8

; The block's own codes, in B.
SD_ENOCARD      equ 1           ; no card in the slot
SD_ECMD0        equ 2           ; init: no answer to CMD0
SD_ECMD8        equ 3           ; init: CMD8 refused or its echo wrong
SD_EACMD41      equ 4           ; init: not ready within SD_TO_INIT
SD_ECMD58       equ 5           ; init: CMD58 refused
SD_ECMD16       equ 6           ; init: CMD16 refused (SDSC)
SD_ECSD         equ 7           ; init: the CSD not read
SD_ECID         equ 8           ; init: the CID not read
SD_ECHANGED     equ 0F0h        ; the card changed since init
SD_ETIMEOUT     equ 0FFh        ; a wait ran out

; The commands, with the start bits in.
SDC_CMD0        equ 40h         ; GO_IDLE_STATE
SDC_CMD8        equ 48h         ; SEND_IF_COND
SDC_CMD9        equ 49h         ; SEND_CSD
SDC_CMD10       equ 4Ah         ; SEND_CID
SDC_CMD12       equ 4Ch         ; STOP_TRANSMISSION
SDC_CMD16       equ 50h         ; SET_BLOCKLEN
SDC_CMD17       equ 51h         ; READ_SINGLE_BLOCK
SDC_CMD18       equ 52h         ; READ_MULTIPLE_BLOCK
SDC_ACMD23      equ 57h         ; SET_WR_BLK_ERASE_COUNT
SDC_CMD24       equ 58h         ; WRITE_BLOCK
SDC_CMD25       equ 59h         ; WRITE_MULTIPLE_BLOCK
SDC_ACMD41      equ 69h         ; SD_SEND_OP_COND
SDC_CMD55       equ 77h         ; APP_CMD
SDC_CMD58       equ 7Ah         ; READ_OCR
SD_TOK_READ     equ 0FEh        ; the data token of a read, and a CMD24
SD_TOK_MBW      equ 0FCh        ; the data token of a CMD25 sector
SD_TOK_STOP     equ 0FDh        ; CMD25's stop token
; The bounds, in ticks, rounded up from the specification's: 100 ms for
; a read's token, 500 ms for a write's busy, 1 s for ACMD41.
SD_TO_READ      equ 7
SD_TO_WRITE     equ 31
SD_TO_INIT      equ 61
SD_CMD0_TRIES   equ 8

; init — both slots brought up; A = 2 always, CF clear.
sd_init:
        ld      a,1
        call    sd_init_slot
        ld      a,2
        call    sd_init_slot
        ld      a,2
        or      a
        ret

; sd_init_slot — A = slot: its record cleared and filled. Corrupts
; everything but IX.
sd_init_slot:
        ld      (ix+SD_CARD),a
        call    sd_slot                 ; iy -> the record
        push    iy
        pop     hl
        ld      d,h
        ld      e,l
        inc     de
        ld      (hl),0
        ld      bc,SD_SLOT-1
        ldir
        sdp_deselect
        ld      b,10                    ; 80 clocks with every CS off
.clk:   ld      a,0FFh
        sdp_out
        djnz    .clk
        ld      a,(ix+SD_CARD)
        sdp_select
        ld      a,(SDP_SENSE)
        and     SDF_ABSENT|SDF_PROT     ; the change latch, set at power-on
        ld      (iy+SD_FLAGS),a         ; and while the slot was empty, is
        bit     1,a                     ; dropped: this is the initialisation
        ld      a,SD_ENOCARD            ; a change asks for
        jp      nz,.nocard
        ld      b,SD_CMD0_TRIES
.cmd0:  push    bc
        ld      a,SDC_CMD0
        ld      bc,0
        ld      de,0
        call    sd_cmd
        pop     bc
        jr      c,.next0
        cp      01h
        jr      z,.idle
.next0: djnz    .cmd0
        ld      a,SD_ECMD0
        jp      .failed
.idle:  ld      (ix+SD_V2),0
        ld      a,SDC_CMD8
        ld      bc,0
        ld      de,01AAh                ; 2.7-3.6 V, the check pattern
        call    sd_cmd
        jr      c,.e8
        bit     2,a                     ; illegal: a version 1 card
        jr      nz,.op
        cp      01h
        jr      nz,.e8
        sdp_in                          ; R7: four bytes, the low twelve
        sdp_in                          ; bits echo the argument
        sdp_in
        and     0Fh
        cp      01h
        jr      nz,.e8
        sdp_in
        cp      0AAh
        jr      nz,.e8
        ld      (ix+SD_V2),1
        jr      .op
.e8:    ld      a,SD_ECMD8
        jp      .failed
.op:    call    sd_t0
.op41:  ld      a,SDC_ACMD41
        ld      bc,0
        bit     0,(ix+SD_V2)
        jr      z,.hcs
        ld      b,40h                   ; HCS: a high-capacity card may say so
.hcs:   ld      de,0
        call    sd_acmd
        jr      c,.e41
        or      a
        jr      z,.ready
        and     7Eh                     ; an error bit: not an SD card
        jr      nz,.e41
        ld      b,SD_TO_INIT
        call    sd_elapsed
        jr      c,.op41
.e41:   ld      a,SD_EACMD41
        jr      .failed
.ready: ld      (iy+SD_STATE),1         ; SDSC unless CCS says otherwise
        bit     0,(ix+SD_V2)
        jr      z,.blen
        ld      a,SDC_CMD58
        ld      bc,0
        ld      de,0
        call    sd_cmd
        jr      c,.e58
        or      a
        jr      nz,.e58
        sdp_in                          ; the OCR's high byte: bit 30 CCS
        ld      l,a
        sdp_in
        sdp_in
        sdp_in
        bit     6,l
        jr      z,.blen
        ld      (iy+SD_STATE),2
        jr      .csd
.e58:   ld      a,SD_ECMD58
        jr      .failed
.blen:  ld      a,SDC_CMD16             ; a standard-capacity card: 512
        ld      bc,0
        ld      de,512
        call    sd_cmd
        jr      c,.e16
        or      a
        jr      z,.csd
.e16:   ld      a,SD_ECMD16
        jr      .failed
.csd:   ld      a,SDC_CMD9
        push    iy
        pop     de
        ld      hl,SD_CID               ; the CSD read over the CID's
        add     hl,de                   ; bytes, then the CID over it
        ex      de,hl
        call    sd_read16
        ld      a,SD_ECSD
        jr      c,.failed
        call    sd_csd_total
        ld      a,SDC_CMD10
        push    iy
        pop     de
        ld      hl,SD_CID
        add     hl,de
        ex      de,hl
        call    sd_read16
        ld      a,SD_ECID
        jr      c,.failed
        jr      .done
.failed:
        ld      (iy+SD_CODE),a
        ld      (iy+SD_STATE),0
        set     7,(iy+SD_FLAGS)
        jr      .done
.nocard:
        ld      (iy+SD_CODE),a
.done:  sdp_deselect
        sdp_in
        ret

; sd_read16 — A = CMD9 or CMD10, DE -> 16 bytes: the command, its token
; and the register, the CRC discarded. CF on a refusal, a bad token or
; a timeout. Corrupts everything but IX, IY.
sd_read16:
        ld      bc,0
        push    de
        ld      de,0
        call    sd_cmd
        pop     de
        ret     c
        or      a
        scf
        ret     nz
        ld      b,SD_TO_READ
        ld      c,SD_TOK_READ
        call    sd_wait
        ret     c
        ld      b,16
.byte:  sdp_in
        ld      (de),a
        inc     de
        djnz    .byte
        sdp_in
        sdp_in
        or      a
        ret

; sd_csd_total — the CSD at the record's SD_CID: the sector count into
; SD_TOTAL. Version 1: (C_SIZE + 1) << (C_SIZE_MULT + 2 + READ_BL_LEN - 9);
; version 2: (C_SIZE + 1) << 10. Corrupts everything but IX, IY.
sd_csd_total:
        ld      a,(iy+SD_CID+0)
        and     0C0h
        jr      nz,.v2
        ld      a,(iy+SD_CID+6)         ; C_SIZE bits 11-10
        and     03h
        ld      h,a
        ld      a,(iy+SD_CID+7)         ; bits 9-2
        ld      l,a
        add     hl,hl
        add     hl,hl                   ; hl = C_SIZE << 2, bits 11-2 placed
        ld      a,(iy+SD_CID+8)         ; bits 1-0 in bits 7-6
        rlca
        rlca
        and     03h
        or      l
        ld      l,a
        inc     hl                      ; C_SIZE + 1, 13 bits at most
        ld      a,(iy+SD_CID+9)         ; C_SIZE_MULT bits 2-1
        and     03h
        add     a,a
        ld      c,a
        ld      a,(iy+SD_CID+10)        ; bit 0 in bit 7
        rlca
        and     01h
        or      c
        add     a,2
        ld      c,a
        ld      a,(iy+SD_CID+5)         ; READ_BL_LEN
        and     0Fh
        add     a,c
        sub     9                       ; the shift, 0 or more
        ld      c,a
        ld      de,0                    ; de:hl = C_SIZE + 1
        jr      .shift
.v2:    ld      a,(iy+SD_CID+7)
        and     3Fh
        ld      e,a
        ld      h,(iy+SD_CID+8)
        ld      l,(iy+SD_CID+9)
        ld      d,0
        inc     hl                      ; (no flags from a 16-bit inc)
        ld      a,h
        or      l
        jr      nz,.v2c
        inc     de
.v2c:   ld      c,10
.shift: ld      a,c
        or      a
        jr      z,.store
.one:   add     hl,hl
        rl      e
        rl      d
        dec     c
        jr      nz,.one
.store: ld      (iy+SD_TOTAL),l
        ld      (iy+SD_TOTAL+1),h
        ld      (iy+SD_TOTAL+2),e
        ld      (iy+SD_TOTAL+3),d
        ret

; info — A = device, HL -> the DI_SIZE buffer in page 2.
sd_info:
        ld      c,a
        dec     a
        cp      2
        jp      nc,sd_nxio
        inc     a
        call    sd_slot
        push    hl                      ; the buffer zeroed
        ld      (hl),0
        ld      d,h
        ld      e,l
        inc     de
        push    bc
        ld      bc,DI_SIZE-1
        ldir
        pop     bc
        pop     hl
        ld      a,(iy+SD_FLAGS)
        and     SDF_PROT
        ld      e,DIF_REMOVABLE
        jr      z,.flags
        ld      e,DIF_REMOVABLE|DIF_RO
.flags: ld      a,(iy+SD_STATE)
        or      a
        jr      nz,.card
        ld      a,DIF_NOMEDIUM
        or      e
        ld      (hl),a
        push    hl
        push    bc
        ld      de,DI_NAME
        add     hl,de
        ex      de,hl
        ld      hl,sdp_s_slot
        ld      bc,32
        ldir
        pop     bc
        ld      hl,8-32                 ; the slot's digit, after "SD slot "
        add     hl,de
        ld      a,c
        add     a,'0'
        ld      (hl),a
        pop     hl
        jr      .ident
.card:  ld      (hl),e
        push    hl
        push    bc
        ld      bc,DI_COUNT
        add     hl,bc
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SD_TOTAL
        add     hl,bc
        ld      bc,4
        ldir
        pop     bc
        pop     hl
        push    hl
        push    bc
        ld      bc,DI_NAME
        add     hl,bc
        ex      de,hl                   ; de -> the name
        push    iy
        pop     hl
        ld      bc,SD_CID+3             ; the product name, five bytes
        add     hl,bc
        ld      bc,5
        ldir
        ld      a,' '
        ld      (de),a
        inc     de
        ld      a,(hl)                  ; the revision, n.m
        inc     hl
        push    af
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        add     a,'0'
        ld      (de),a
        inc     de
        ld      a,'.'
        ld      (de),a
        inc     de
        pop     af
        and     0Fh
        add     a,'0'
        ld      (de),a
        inc     de
        ld      a,' '
        ld      (de),a
        inc     de
        ld      hl,sdp_s_sdhc
        ld      a,(iy+SD_STATE)
        cp      2
        jr      z,.class
        ld      hl,sdp_s_sdsc
.class: ld      bc,4
        ldir
        ld      a,' '
        ld      b,32-14
.pad:   ld      (de),a
        inc     de
        djnz    .pad
        pop     bc
        pop     hl
.ident: ld      de,DI_IDENT
        add     hl,de
        ld      (hl),7Fh                ; slot: none (docs/drivers.md)
        inc     hl
        ld      (hl),c                  ; the device, as Nextor's would be
        inc     hl
        ld      (hl),1                  ; its unit
        inc     hl
        inc     hl
        ld      a,(iy+SD_STATE)
        or      a
        jr      z,.ok
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SD_CID+9             ; the serial, four bytes
        add     hl,bc
        ld      bc,4
        ldir
        ld      a,(iy+SD_CID+0)         ; the manufacturer
        ld      (de),a
        inc     de
        ld      a,(iy+SD_CID+1)         ; the OEM, two bytes
        ld      (de),a
        inc     de
        ld      a,(iy+SD_CID+2)
        ld      (de),a
.ok:    xor     a
        ld      b,a
        ret

; status — A = device: the sense read; a changed slot, or an empty one
; with a card in now, re-initialised: DS_CHANGED with a card, else
; DS_NOTAVAIL; DS_SAME otherwise.
sd_status:
        ld      c,a
        dec     a
        cp      2
        jr      nc,sd_nxio
        ld      a,c
        call    sd_slot
        call    sd_sense
        bit     1,a                     ; absent now
        jr      nz,.gone
        ld      a,(iy+SD_FLAGS)
        bit     0,a
        jr      nz,.again
        ld      a,(iy+SD_STATE)
        or      a
        jr      z,.again                ; a card where there was none
        ld      a,DS_SAME
        ret
.again: ld      a,c
        call    sd_init_slot
        ld      a,(iy+SD_STATE)
        or      a
        ld      a,DS_CHANGED
        ret     nz
.gone:  ld      (iy+SD_STATE),0
        ld      (iy+SD_CODE),SD_ENOCARD
        ld      a,DS_NOTAVAIL
        or      a
        ret

; sd_sense — the call's slot selected, SDP_SENSE read and folded into the
; record's flags (a set bit stays set until init clears it), the card
; deselected. A = the flags. Preserves BC, DE, HL.
sd_sense:
        ld      a,c
        sdp_select
        ld      a,(SDP_SENSE)
        and     SDF_CHANGED|SDF_ABSENT|SDF_PROT
        or      (iy+SD_FLAGS)
        ld      (iy+SD_FLAGS),a
        sdp_deselect
        ld      a,(iy+SD_FLAGS)
        ret

; query — DQ_PRIVATE: the device's record, SD_SLOT bytes, to HL in page
; 2. Everything else E_NOSYS.
sd_query:
        ld      c,a
        ld      a,b
        cp      DQ_PRIVATE
        jr      nz,sd_nosys
        ld      a,c
        dec     a
        cp      2
        jr      nc,sd_nxio
        ld      a,c
        call    sd_slot
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SD_SLOT
        ldir
        xor     a
        ld      b,a
        ret
sd_nosys:
        ld      b,0
        ld      a,E_NOSYS
        scf
        ret
sd_nxio:
        ld      b,0
        ld      a,E_NXIO
        scf
        ret

; rw — A = device, CF = write, B = count 1-32, C = slot, DE:HL = sector.
sd_rw:
        push    af
        ld      a,0
        rla
        ld      (ix+SD_WR),a
        ld      (ix+SD_N),b
        ld      a,c
        add     a,80h
        ld      (ix+SD_TGT),a
        pop     af
        ld      c,a
        dec     a
        cp      2
        jr      nc,sd_nxio
        ld      a,c
        ld      (ix+SD_CARD),a
        call    sd_slot
        ld      a,(iy+SD_STATE)
        or      a
        jr      z,.nocard
        bit     0,(iy+SD_FLAGS)
        jr      nz,.changed
        bit     0,(ix+SD_WR)
        jr      z,.range
        bit     2,(iy+SD_FLAGS)
        jr      nz,.rofs
.range: ; sector + count <= total, in 32 bits, before the card is
        ; touched: a standard-capacity card's byte address cannot
        ; overflow then either.
        push    hl
        push    de
        ld      c,b
        ld      b,0
        add     hl,bc
        jr      nc,.nc
        inc     de
.nc:    ld      c,(iy+SD_TOTAL)
        ld      b,(iy+SD_TOTAL+1)
        ex      de,hl                   ; hl = end high, de = end low
        push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de                   ; total low - end low
        pop     de
        ld      l,(iy+SD_TOTAL+2)
        ld      h,(iy+SD_TOTAL+3)
        sbc     hl,de                   ; total high - end high - borrow
        pop     de
        pop     hl
        jr      c,.eio
        push    hl
        push    de
        ld      c,(ix+SD_CARD)
        call    sd_sense                ; the slot as it is now
        pop     de
        pop     hl
        bit     1,a
        jr      nz,.nocard
        bit     0,a
        jr      nz,.changed
        bit     0,(ix+SD_WR)
        jr      z,.go
        bit     2,a
        jr      nz,.rofs
.go:    call    sd_bytes                ; bc:de = the argument
        ld      a,(ix+SD_CARD)
        sdp_select
        bit     0,(ix+SD_WR)
        jp      nz,sd_write
        jp      sd_read
.nocard:
        ld      b,(iy+SD_CODE)
        ld      a,E_NXIO
        scf
        ret
.changed:
        ld      b,SD_ECHANGED
        ld      a,E_NXIO
        scf
        ret
.rofs:  ld      b,0
        ld      a,E_ROFS
        scf
        ret
.eio:   ld      b,0
        ld      a,E_IO
        scf
        ret

; sd_read — the card selected, BC:DE the argument: CMD17 for one
; sector, CMD18 and CMD12 for more.
sd_read:
        ld      a,SDC_CMD17
        dec     (ix+SD_N)
        jr      z,.cmd
        inc     (ix+SD_N)
        ld      a,SDC_CMD18
        call    sd_cmd
        jp      c,sd_fail
        or      a
        jp      nz,sd_fail
.sector:
        call    sd_rd_sector
        jp      c,sd_fail
        dec     (ix+SD_N)
        jr      nz,.sector
        ld      a,SDC_CMD12             ; its response after a stuff
        ld      bc,0                    ; byte, not judged; then the busy
        ld      de,0                    ; the specification allows
        call    sd_cmd_stuff
        ld      b,SD_TO_WRITE
        ld      c,0
        call    sd_wait
        jp      c,sd_fail
        jp      sd_end
.cmd:   call    sd_cmd
        jp      c,sd_fail
        or      a
        jp      nz,sd_fail
        call    sd_rd_sector
        jp      c,sd_fail
        jp      sd_end

; sd_write — the card selected, BC:DE the argument: CMD24 for one
; sector; ACMD23 (its answer not judged), CMD25, the stop token and the
; busy for more.
sd_write:
        ld      a,SDC_CMD24
        dec     (ix+SD_N)
        jr      z,.cmd
        inc     (ix+SD_N)
        push    bc
        push    de
        ld      a,SDC_ACMD23
        ld      bc,0
        ld      d,c
        ld      e,(ix+SD_N)
        call    sd_acmd
        pop     de
        pop     bc
        ld      a,SDC_CMD25
        call    sd_cmd
        jp      c,sd_fail
        or      a
        jp      nz,sd_fail
        sdp_in                          ; Nwr: a byte before the token
.sector:
        ld      c,SD_TOK_MBW
        call    sd_wr_sector
        jp      c,sd_fail
        sdp_in
        dec     (ix+SD_N)
        jr      nz,.sector
        ld      a,SD_TOK_STOP
        sdp_out
        sdp_in
        ld      b,SD_TO_WRITE
        ld      c,0
        call    sd_wait
        jp      c,sd_fail
        jp      sd_end
.cmd:   call    sd_cmd
        jp      c,sd_fail
        or      a
        jp      nz,sd_fail
        sdp_in                          ; Nwr
        ld      c,SD_TOK_READ
        call    sd_wr_sector
        jp      c,sd_fail
        jp      sd_end

; sd_rd_sector — the next sector of the call into its target: the token
; waited for, 512 bytes in, the CRC discarded. CF with A = the token or
; SD_ETIMEOUT. Corrupts everything but IX, IY.
sd_rd_sector:
        ld      b,SD_TO_READ
        ld      c,SD_TOK_READ
        call    sd_wait
        ret     c
        ld      d,(ix+SD_TGT)
        ld      e,0
        sdp_in512
        inc     (ix+SD_TGT)
        inc     (ix+SD_TGT)
        sdp_in
        sdp_in
        or      a
        ret

; sd_wr_sector — C = the token: the next sector of the call sent after
; it with a dummy CRC, the data response read within eight bytes and
; judged (accepted = 05h in its low five bits), then the busy. CF with
; A = the response or SD_ETIMEOUT.
sd_wr_sector:
        ld      a,c
        sdp_out
        ld      h,(ix+SD_TGT)
        ld      l,0
        sdp_out512
        inc     (ix+SD_TGT)
        inc     (ix+SD_TGT)
        ld      a,0FFh
        sdp_out
        sdp_out
        ld      b,8
.resp:  sdp_in
        cp      0FFh
        jr      nz,.got
        djnz    .resp
        ld      a,SD_ETIMEOUT
        scf
        ret
.got:   ld      c,a
        and     1Fh
        cp      05h
        ld      a,c
        scf
        ret     nz
        ld      b,SD_TO_WRITE
        ld      c,0
        jp      sd_wait

; sd_end — the call done: the card deselected, a byte after it; A = 0,
; B = 0, CF clear. sd_fail — A = the card's byte or SD_ETIMEOUT: the
; same, then E_IO with B = that byte.
sd_end:
        sdp_deselect
        sdp_in
        xor     a
        ld      b,a
        ret
sd_fail:
        ld      b,a
        sdp_deselect
        sdp_in
        ld      a,E_IO
        scf
        ret

; sd_bytes — DE:HL = the sector: BC:DE = the command's argument, the
; sector on a high-capacity card, sector x 512 on a standard-capacity
; one. Corrupts A, HL.
sd_bytes:
        ld      a,(iy+SD_STATE)
        cp      2
        jr      z,.sectors
        ld      b,e                     ; << 8
        ld      c,h
        ld      d,l
        ld      e,0
        sla     d                       ; << 1
        rl      c
        rl      b
        ret
.sectors:
        ld      b,d
        ld      c,e
        ld      d,h
        ld      e,l
        ret

; sd_cmd — A = the command, BC:DE = its argument: eight clocks, the six
; bytes, then the response within eight bytes. A = R1, CF clear; or CF
; set and A = SD_ETIMEOUT when none came. sd_cmd_stuff: the same with
; one byte discarded before the response (CMD12). Corrupts HL. Preserve
; BC, DE.
sd_cmd_stuff:
        ld      l,1
        jr      sd_cmd.go
sd_cmd:
        ld      l,0
.go:    ld      h,a
        sdp_in
        ld      a,h
        sdp_out
        ld      a,b
        sdp_out
        ld      a,c
        sdp_out
        ld      a,d
        sdp_out
        ld      a,e
        sdp_out
        ld      a,h
        cp      SDC_CMD0
        ld      a,95h                   ; CMD0's CRC
        jr      z,.crc
        ld      a,h
        cp      SDC_CMD8
        ld      a,87h                   ; CMD8's
        jr      z,.crc
        ld      a,01h                   ; the stop bit alone otherwise
.crc:   sdp_out
        dec     l
        jr      nz,.resp
        sdp_in                          ; the stuff byte
.resp:  ld      h,8
.r:     sdp_in
        bit     7,a
        jr      z,.got
        dec     h
        jr      nz,.r
        ld      a,SD_ETIMEOUT
        scf
        ret
.got:   or      a
        ret

; sd_acmd — CMD55 then the command in A with BC:DE; CMD55's answer is
; good with no error bit (the idle bit allowed). Out as sd_cmd, CF with
; A = SD_ETIMEOUT or CMD55's R1 when it refused.
sd_acmd:
        push    af
        push    bc
        push    de
        ld      a,SDC_CMD55
        ld      bc,0
        ld      de,0
        call    sd_cmd
        pop     de
        pop     bc
        jr      c,.no
        and     7Eh
        jr      nz,.no
        pop     af
        jr      sd_cmd
.no:    ld      l,a
        pop     af
        ld      a,l
        scf
        ret

; sd_wait — C = the byte waited for, or 0 for anything but 00h (busy);
; B = the bound in ticks: polled until it comes. CF clear and A = the
; byte; or CF set and A = a data error token (01h-0Fh, while waiting for
; a token) or SD_ETIMEOUT. Corrupts HL. Preserves BC, DE.
sd_wait:
        call    sd_t0
.poll:  sdp_in
        ld      l,a
        ld      a,c
        or      a
        jr      z,.busy
        ld      a,l
        cp      c
        ret     z
        or      a
        jr      z,.more
        cp      10h
        jr      c,.token
.more:  call    sd_elapsed
        jr      c,.poll
        ld      a,SD_ETIMEOUT
        scf
        ret
.busy:  ld      a,l
        or      a
        ret     nz
        jr      .more
.token: scf
        ret

; sd_t0 — the tick now into SD_T0. sd_elapsed — CF set while fewer than
; B ticks have passed since it. Both preserve A, BC, DE.
sd_t0:  ld      hl,(K_TICKS)
        ld      (ix+SD_T0),l
        ld      (ix+SD_T0+1),h
        ret
sd_elapsed:
        push    de
        ld      hl,(K_TICKS)
        ld      e,(ix+SD_T0)
        ld      d,(ix+SD_T0+1)
        or      a
        sbc     hl,de
        ld      d,0
        ld      e,b
        sbc     hl,de
        pop     de
        ret

; sd_slot — A = slot 1 or 2: IY -> its record. Preserves A, BC, DE, HL.
sd_slot:
        push    hl
        push    de
        push    ix
        pop     hl
        ld      de,0
        cp      2
        jr      nz,.add
        ld      de,SD_SLOT
.add:   add     hl,de
        push    hl
        pop     iy
        pop     de
        pop     hl
        ret
