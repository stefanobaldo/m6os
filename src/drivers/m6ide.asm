; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; m6ide — the Sunrise IDE driver, a block written to m6's contract
; (docs/drivers.md) from the ATA specification, for the driver bank of
; the Sunrise kernel ROM. The master and the slave are devices 1 and 2.
; A call of B sectors is one READ SECTORS or WRITE SECTORS with the count
; register set to B: per sector the driver waits for DRQ and moves 512
; bytes with an unrolled LDI, interrupts enabled throughout — nothing
; here disables them, since the handler never touches page 1 and the
; data register's latch survives an interrupt between two bytes. Every
; wait is bounded by the tick. Init finds each position by selecting it,
; waiting for BSY to clear, writing two registers and reading them back
; (a position nobody answers from reads the floating bus, or a master
; mirroring itself), then IDENTIFY, whose model, serial and total it
; keeps; an ATAPI device aborts IDENTIFY and is treated as absent; a
; soft reset is issued once, only when neither position answered at all.
; Nothing is printed, and nothing of page 0 or page 2 is written outside
; what the contract says.
;
; The cartridge's control register, 4104h, holds the ROM bank in bits
; 7-5 and, in bit 0, whether the IDE registers show in page 1 in place
; of the ROM at 7C00h-7EFFh; CHGBNK clears that bit, so the kernel
; enters a routine with the registers off, and every routine that
; touches the device turns them on at entry and off before returning.
; With them on this bank's bytes from 7C00h are unreadable, so the
; block ends below that address (the assertion at the end).
; Included at DRV_BASE of the ROM's bank 7 by src/rom/rom.asm, which
; has kernel.inc in already. Variables: SI_RAM bytes of page 3, IX on
; every entry.

SI_CTRL         equ 4104h       ; bit 0: the IDE registers in page 1
SI_ON           equ 0E1h        ; bank 7 (bits 7-5), registers on
SI_OFF          equ 0E0h        ; bank 7, registers off
SI_DATA         equ 7C00h       ; the data register, mirrored to 7DFFh
SI_ERR          equ 7E01h       ; error (read)
SI_COUNT        equ 7E02h       ; sector count
SI_LBA0         equ 7E03h       ; LBA 0-7
SI_LBA1         equ 7E04h       ; LBA 8-15
SI_LBA2         equ 7E05h       ; LBA 16-23
SI_DEV          equ 7E06h       ; bit 4 the device, bits 0-3 LBA 24-27
SI_STAT         equ 7E07h       ; status (read)
SI_CMD          equ 7E07h       ; command (write)
SI_DCTL         equ 7E0Eh       ; device control (write)
SIS_BSY         equ 80h
SIS_DRQ         equ 08h
SIS_DF          equ 20h
SIS_ERR         equ 01h
SI_DEVBASE      equ 0E0h        ; LBA, bits 7 and 5 set: the device byte
SIC_READ        equ 20h         ; READ SECTORS
SIC_WRITE       equ 30h         ; WRITE SECTORS
SIC_IDENT       equ 0ECh        ; IDENTIFY DEVICE
SI_TO_CMD       equ 120         ; ticks: BSY or DRQ on a command, 2 s
SI_TO_RST       equ 300         ; ticks: BSY after a soft reset, 5 s

; The RAM: a record per position, then the call's variables.
SI_STATE        equ 0           ; 1 present, 0 absent
SI_TOTAL        equ 1           ; 4: sectors
SI_MODEL        equ 5           ; 32: IDENTIFY words 27-42, bytes swapped
SI_SERIAL       equ 37          ; 12: IDENTIFY words 10-15, bytes swapped
SI_POS          equ 50          ; a position's record; +49 reserved
SI_T0           equ 100         ; 2: the tick at the current wait's entry
SI_TGT          equ 102         ; the high byte of the sector's target
SI_N            equ 103         ; sectors left in the call
SI_WR           equ 104         ; 1 = a write
SI_POSN         equ 105         ; the call's position, 0 or 1
SI_ANS          equ 106         ; bit n: position n answered at init
SI_LBAF         equ 107         ; the high byte of IDENTIFY's word 49
SI_RAM          equ 108

        db      "M6DRV"                 ; DRV_SIGN
        db      DRV_VER_1               ; DRV_VER
        db      0                       ; DRV_FLAGS
        jp      si_init                 ; DRV_INIT
        jp      si_info                 ; DRV_INFO
        jp      si_status               ; DRV_STATUS
        jp      si_rw                   ; DRV_RW
        jp      si_query                ; DRV_QUERY
        jp      si_nosys                ; DRV_RES1
        jp      si_nosys                ; DRV_RES2
        dw      SI_RAM                  ; DRV_RAM
        dw      0                       ; DRV_RELOC
        db      "m6ide           "      ; DRV_NAME
        ASSERT  $-DRV_BASE == DRV_HDR

; init — both positions probed, a soft reset once when neither answers,
; then IDENTIFY on each that did. A = 2 when the slave is present, else
; 1: the master, or, with nothing at all, the "no volumes" line info
; gives device 1 then. CF clear always.
si_init:
        call    si_on
        ld      (ix+SI_ANS),0
        xor     a
        call    si_probe
        ld      a,1
        call    si_probe
        ld      a,(ix+SI_ANS)
        or      a
        jr      nz,.answered
        ; Neither answered: SRST with nIEN, at least 5 us, then nIEN
        ; alone, a tick (at least 2 ms), and the probes again with the
        ; long wait.
        ld      a,06h
        ld      (SI_DCTL),a
        ex      (sp),hl
        ex      (sp),hl
        ld      a,02h
        ld      (SI_DCTL),a
        call    si_tick
        ld      de,SI_TO_RST
        xor     a
        call    si_probe_de
        ld      de,SI_TO_RST
        ld      a,1
        call    si_probe_de
.answered:
        ld      a,02h                   ; nIEN: the interface routes no
        ld      (SI_DCTL),a             ; INTRQ, and the device need not
                                        ; raise one
        xor     a
        call    si_identify
        ld      a,1
        call    si_identify
        call    si_off
        ld      a,(ix+SI_POS+SI_STATE)
        or      a
        ld      a,2
        ret     nz
        dec     a
        ret

; si_probe — A = position: selected, BSY waited for with the command
; timeout; a position whose BSY clears sets its bit in SI_ANS.
; si_probe_de: the same with the timeout in DE. Corrupts everything.
si_probe:
        ld      de,SI_TO_CMD
si_probe_de:
        ld      c,a
        rrca
        rrca
        rrca
        rrca                            ; the position into bit 4
        or      SI_DEVBASE
        call    si_select
        call    si_wait_bsy
        ret     c
        ld      a,c
        or      a
        ld      a,1
        jr      z,.bit
        ld      a,2
.bit:   or      (ix+SI_ANS)
        ld      (ix+SI_ANS),a
        ret

; si_identify — A = position: when it answered, the presence test and
; IDENTIFY; the record filled and SI_STATE set when the device is ATA
; with LBA. Corrupts everything.
si_identify:
        ld      c,a
        inc     c                       ; c = the position's bit, 1 or 2
        ld      a,(ix+SI_ANS)
        and     c
        ret     z
        ld      a,c
        dec     a
        call    si_pos                  ; iy -> its record
        rrca
        rrca
        rrca
        rrca
        or      SI_DEVBASE
        call    si_select
        ld      de,SI_TO_CMD
        call    si_wait_bsy
        ret     c
        ; Two registers written and read back: a device echoes them, a
        ; floating bus or a master answering for an absent slave does not.
        ld      a,55h
        ld      (SI_COUNT),a
        ld      a,0AAh
        ld      (SI_LBA0),a
        ld      a,(SI_COUNT)
        cp      55h
        ret     nz
        ld      a,(SI_LBA0)
        cp      0AAh
        ret     nz
        ld      a,SIC_IDENT
        ld      (SI_CMD),a
        ld      de,SI_TO_CMD
        call    si_wait_drq
        ret     c                       ; ERR (an ATAPI device aborts) or
                                        ; a timeout: absent
        ld      (ix+SI_LBAF),0
        ld      bc,0                    ; b = 256 words, c = the index
.word:  ld      a,(SI_DATA)
        ld      e,a
        ld      a,(SI_DATA+1)
        ld      d,a
        call    si_ident_word
        inc     c
        djnz    .word
        bit     1,(ix+SI_LBAF)          ; word 49 bit 9: LBA supported
        ret     z
        ld      (iy+SI_STATE),1
        ret

; si_ident_word — C = the word's index, D:E the word: what the record
; keeps of it. Preserves BC.
si_ident_word:
        ld      a,c
        cp      10
        ret     c
        cp      16
        jr      c,.serial               ; 10-15
        cp      27
        ret     c
        cp      43
        jr      c,.model                ; 27-42
        cp      49
        jr      z,.lba
        cp      60
        jr      z,.tot0
        cp      61
        ret     nz
        ld      (iy+SI_TOTAL+2),e
        ld      (iy+SI_TOTAL+3),d
        ret
.tot0:  ld      (iy+SI_TOTAL),e
        ld      (iy+SI_TOTAL+1),d
        ret
.lba:   ld      (ix+SI_LBAF),d
        ret
.serial:
        sub     10
        add     a,a
        add     a,SI_SERIAL
        jr      .pair
.model: sub     27
        add     a,a
        add     a,SI_MODEL
.pair:  push    de                      ; the record's byte: the high
        ld      e,a                     ; byte first, as ATA strings are
        ld      d,0
        push    iy
        pop     hl
        add     hl,de
        pop     de
        ld      (hl),d
        inc     hl
        ld      (hl),e
        ret

; info — A = device, HL -> the DI_SIZE buffer in page 2.
si_info:
        ld      c,a                     ; the device number
        dec     a
        cp      2
        jp      nc,si_nxio
        call    si_pos
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
        ld      a,(iy+SI_STATE)
        or      a
        jr      z,.absent
        push    hl
        push    bc
        ld      bc,DI_COUNT
        add     hl,bc
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SI_TOTAL
        add     hl,bc
        ld      bc,4
        ldir
        pop     bc
        pop     hl
        push    hl
        push    bc
        ld      bc,DI_NAME
        add     hl,bc
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SI_MODEL
        add     hl,bc
        ld      bc,32
        ldir
        pop     bc
        pop     hl
        ld      de,DI_IDENT
        add     hl,de
        ld      (hl),7Fh                ; slot: none (docs/drivers.md)
        inc     hl
        ld      (hl),c                  ; the device, as Nextor's would be
        inc     hl
        ld      (hl),1                  ; its unit
        inc     hl
        inc     hl
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,SI_SERIAL
        add     hl,bc
        ld      bc,12
        ldir
        xor     a
        ld      b,a
        ret
.absent:
        ; Device 1 with nothing at all: the controller's own line.
        dec     c
        jp      nz,si_nxio
        ld      a,(ix+SI_POS+SI_STATE)
        or      a
        jp      nz,si_nxio
        ld      (hl),DIF_NOMEDIUM
        push    hl
        ld      bc,DI_NAME
        add     hl,bc
        ex      de,hl
        ld      hl,si_s_name
        ld      bc,32
        ldir
        pop     hl
        ld      bc,DI_IDENT
        add     hl,bc
        ld      (hl),7Fh
        inc     hl
        ld      (hl),1
        inc     hl
        ld      (hl),1
        xor     a
        ld      b,a
        ret

; status — A = device: DS_SAME present, DS_NOTAVAIL absent.
si_status:
        dec     a
        cp      2
        jr      nc,si_nxio
        call    si_pos
        ld      a,(iy+SI_STATE)         ; 1 = DS_SAME, 0 = DS_NOTAVAIL
        or      a
        ret

; query — nothing yet.
si_query:
si_nosys:
        ld      b,0
        ld      a,E_NOSYS
        scf
        ret
si_nxio:
        ld      b,0
        ld      a,E_NXIO
        scf
        ret

; rw — A = device, CF = write, B = count 1-32, C = slot, DE:HL = sector.
si_rw:
        push    af
        ld      a,0
        rla
        ld      (ix+SI_WR),a
        ld      (ix+SI_N),b
        ld      a,c
        add     a,80h
        ld      (ix+SI_TGT),a
        pop     af
        dec     a
        cp      2
        jr      nc,si_nxio
        ld      (ix+SI_POSN),a
        call    si_pos
        ld      a,(iy+SI_STATE)
        or      a
        jr      z,si_nxio
        ; sector + count <= total, in 32 bits, before the device is
        ; touched: the device's own answer to a range past its end is
        ; not relied on.
        push    hl
        push    de
        ld      c,b
        ld      b,0
        add     hl,bc
        jr      nc,.nc
        inc     de
.nc:    ld      c,(iy+SI_TOTAL)
        ld      b,(iy+SI_TOTAL+1)
        ex      de,hl                   ; hl = end high, de = end low
        push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de                   ; total low - end low
        pop     de
        ld      l,(iy+SI_TOTAL+2)
        ld      h,(iy+SI_TOTAL+3)
        sbc     hl,de                   ; total high - end high - borrow
        pop     de
        pop     hl
        jp      c,.eio
        call    si_on
        ld      a,(ix+SI_POSN)
        rrca
        rrca
        rrca
        rrca
        or      SI_DEVBASE
        ld      c,a
        ld      a,d
        and     0Fh
        or      c
        call    si_select
        push    hl
        push    de
        ld      de,SI_TO_CMD
        call    si_wait_bsy
        pop     de
        pop     hl
        jp      c,si_fail
        ld      a,l
        ld      (SI_LBA0),a
        ld      a,h
        ld      (SI_LBA1),a
        ld      a,e
        ld      (SI_LBA2),a
        ld      a,(ix+SI_N)
        ld      (SI_COUNT),a
        ld      a,SIC_READ
        bit     0,(ix+SI_WR)
        jr      z,.cmd
        ld      a,SIC_WRITE
.cmd:   ld      (SI_CMD),a
.sector:
        ld      de,SI_TO_CMD
        call    si_wait_drq
        jp      c,si_fail
        ld      h,(ix+SI_TGT)
        ld      l,0
        bit     0,(ix+SI_WR)
        jr      nz,.write
        ex      de,hl
        ld      hl,SI_DATA
        call    si_copy
        jr      .next
.write: ld      de,SI_DATA
        call    si_copy
        ld      de,SI_TO_CMD            ; the device reports a write's
        call    si_wait_bsy             ; failure once it has the data
        jp      c,si_fail
        and     SIS_ERR|SIS_DF
        jr      z,.next
        ld      a,(SI_STAT)
        jp      si_fail
.next:  inc     (ix+SI_TGT)
        inc     (ix+SI_TGT)
        dec     (ix+SI_N)
        jr      nz,.sector
        call    si_off
        xor     a
        ld      b,a
        ret
.eio:   ld      b,0
        ld      a,E_IO
        scf
        ret

; si_fail — A = the status register: E_IO, with B the error register
; when ERR is set, the status otherwise; the registers off.
si_fail:
        ld      b,a
        bit     0,a
        jr      z,.code
        ld      a,(SI_ERR)
        ld      b,a
.code:  call    si_off
        ld      a,E_IO
        scf
        ret

; si_on, si_off — the IDE registers into page 1, and out of it.
; Preserve everything but AF.
si_on:  ld      a,SI_ON
        ld      (SI_CTRL),a
        ret
si_off: ld      a,SI_OFF
        ld      (SI_CTRL),a
        ret

; si_select — A = the device byte: written, then ~12 us before the next
; register access, which the Nextor driver's author found some devices
; need. Preserves everything.
si_select:
        ld      (SI_DEV),a
        ex      (sp),hl
        ex      (sp),hl
        ret

; si_pos — A = position 0 or 1: IY -> its record. Preserves A, BC, DE, HL.
si_pos: push    hl
        push    de
        push    ix
        pop     hl
        ld      de,0
        or      a
        jr      z,.add
        ld      de,SI_POS
.add:   add     hl,de
        push    hl
        pop     iy
        pop     de
        pop     hl
        ret

; si_wait_bsy — DE = the timeout in ticks: until BSY is clear. CF clear
; and A = the status; or CF set on the timeout, A = the status then.
; si_wait_drq — the same until DRQ is set with BSY clear; CF set on ERR
; as well. Both corrupt BC, HL.
si_wait_bsy:
        call    si_t0
.loop:  ld      a,(SI_STAT)
        bit     7,a
        jr      nz,.busy
        or      a
        ret
.busy:  call    si_elapsed
        jr      c,.loop
.out:   ld      a,(SI_STAT)
        scf
        ret
si_wait_drq:
        call    si_t0
.loop:  ld      a,(SI_STAT)
        bit     7,a
        jr      nz,.wait
        bit     0,a
        jr      nz,si_wait_bsy.out
        bit     3,a
        jr      z,.wait
        or      a
        ret
.wait:  call    si_elapsed
        jr      c,.loop
        jr      si_wait_bsy.out

; si_t0 — the tick now into SI_T0. si_elapsed — CF set while fewer than
; DE ticks have passed since it. Both preserve A, DE.
si_t0:  ld      hl,(K_TICKS)
        ld      (ix+SI_T0),l
        ld      (ix+SI_T0+1),h
        ret
si_elapsed:
        ld      hl,(K_TICKS)
        ld      c,(ix+SI_T0)
        ld      b,(ix+SI_T0+1)
        or      a
        sbc     hl,bc
        sbc     hl,de
        ret

; si_tick — until the tick changes: at least one tick, 16.7 ms.
si_tick:
        ld      a,(K_TICKS)
        ld      hl,K_TICKS
.w:     cp      (hl)
        jr      z,.w
        ret

; si_copy — 512 bytes from HL to DE: 18 T a byte with the M1 wait, the
; copy the bench measured in both Nextor drivers. Corrupts BC.
si_copy:
        DUP     512
        ldi
        EDUP
        ret

si_s_name:
        db      "Sunrise IDE                     "
        ASSERT  $-si_s_name == 32
        ASSERT  $ <= SI_DATA            ; the registers replace the ROM
                                        ; from here while they are on
