; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; m6sd — the SD driver exercised through the block layer, on the
; emulated SD Mapper V2 with two cards — card 1 an SDHC card whose image
; the harness made read-only, the card's write-protect switch; card 2 a
; standard-capacity card addressed by byte — from the kernel ROM that
; carries the driver (build/m6sd.rom); the same block, with M6SD_LEGACY
; defined (tests/m6sd-legacy), runs through the adapter on the ROM that
; carries the cartridge's Nextor driver, where it asserts less and
; prints the same figures, which is the comparison between the two. A
; kernel-side block the ROM carries in bank 2 after the boot image, run
; as process 0 at 0100h of page 0 as drvrom's is. The report is on
; screen, the verdict in the mailbox. Steps: the record the ROM's boot
; wrote; init, info and status of both devices — the flags (removable,
; card 1 read-only), the names from the CID with the class, the
; driver's own record through its private query; the two volumes; 32
; sectors of a pattern written to card 2's last sectors in one call and
; read back at 1, 8 and 32 per call; a range past the device refused
; before the card is touched, a slot the kernel refuses, a write to the
; protected card refused with E_ROFS, and a third device, then card
; 2's slot found again by status after the driver took it for empty,
; and a read the card ends with a data error token followed by one it
; serves;
; 64 KB read 1, 8 and 32 sectors per call with the real-time clock
; watched — the ticks the kernel counted over the clock's whole
; seconds, against sixty a second: none lost — and the cost per call
; and per sector printed; and a program from the volume reading a 64 KB
; file through read(), its ticks printed. The harness reads card 2's image afterwards
; and compares its last sectors with the pattern. Last, the transfer
; mode: on a cartridge whose block device offers Turbo the kernel put
; the driver in Turbo at boot, and sixteen of the pattern's sectors read
; in Turbo and again in Standard, the mode switched through DQ_MODE,
; must be the same bytes, the mode back in Turbo after; on a cartridge
; without the block the step records that Turbo is not offered. The
; line printed says which. Last, the FAT accelerator's two queries: on
; a device whose block answers them, three tables — FAT32, FAT16 and
; FAT12, every entry c free when c mod 3 = 0 — written to card 2's
; sectors T_FATS up and asked for counts and next free clusters, whole
; and over a one-sector span, a FAT12 entry across two sectors among
; them, and three refusals (a type that is no FAT's, a cluster below 2,
; a table running past the device); on a device without them, E_NOSYS.
; The line printed says which.
        include "m6test.inc"

    IFDEF M6SD_LEGACY
T_SLAVE         equ 8           ; Nextor's device 2, LUN 1, flattened
    ELSE
T_SLAVE         equ 2
    ENDIF
T_TOTAL         equ 4096        ; sectors of each 2 MB image
T_LAST          equ T_TOTAL-32  ; the slave's last 32 sectors
T_FATS          equ T_LAST-32   ; step 9's tables: 8 sectors from here
T_REC2          equ 0F380h-58+24 ; the SD driver's record of slot 2
T_MODE          equ 0F380h-58+56 ; the driver's SD_MODE byte
SD_FLAGS_       equ 1           ; its flags: bit 1 absent
SD_TOTAL_       equ 4           ; its sector count
T_SECTORS       equ 1024        ; sectors read per point of step 6: 8 x 64 KB
T_TOL           equ 2           ; ticks the count may fall short of 60 n:
                                ; the tick rounded at each of the two edges
T_PARAMS        equ 8000h+ST_INFO

tb_start:                               ; SP is the kernel's, at K_END
; --- step 1: the record -----------------------------------------------
        ld      a,1
        call    t_begin
        ld      a,(K_REC+KR_NDRV)
        cp      1
        jp      nz,t_fail
        ld      a,(K_REC+KR_DRVS+KD_KIND)
    IFDEF M6SD_LEGACY
        cp      KD_NEXTOR
    ELSE
        cp      KD_M6
    ENDIF
        jp      nz,t_fail
        ld      a,(K_REC+KR_DRVS+KD_BANK)
        cp      7
        jp      nz,t_fail
    IFNDEF M6SD_LEGACY
        ld      hl,(K_REC+KR_WALL)
        ld      de,0F380h-58            ; SD_RAM
        or      a
        sbc     hl,de
        jp      nz,t_fail
        ld      a,(T_MODE)              ; the mode the kernel's boot chose,
        ld      (t_bootmode),a          ; before step 2's init resets it
    ENDIF
        call    t_ok

; --- step 2: init, info, status ----------------------------------------
        ld      a,2
        call    t_begin
        xor     a                       ; driver 0
        ld      d,BQ_INIT
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
    IFNDEF M6SD_LEGACY
        cp      2
        jp      nz,t_fail
        ld      b,1                     ; device 1: card 1, protected
        ld      c,DIF_REMOVABLE|DIF_RO
        ld      de,ts_name1
        call    t_info
        jp      c,t_fail
        ld      a,(T_PARAMS+DI_CAPS)    ; the init above reset the mode:
        and     DIC_TURBO               ; the kernel's choice made again,
        jr      z,.std2                 ; Turbo where the block offers it
        ld      a,DM_TURBO
        call    t_mode
        jp      c,t_fail
.std2:
        ld      b,T_SLAVE               ; device 2: card 2, SDSC
        ld      c,DIF_REMOVABLE
        ld      de,ts_name2
        call    t_info
        jp      c,t_fail
        ld      b,1                     ; the driver's record: SDHC, the
        ld      c,2                     ; switch seen; SDSC, not
        ld      a,4
        call    t_private
        jp      c,t_fail
        ld      b,T_SLAVE
        ld      c,1
        xor     a
        call    t_private
        jp      c,t_fail
        xor     a
        ld      b,3                     ; no third device
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      nc,t_fail
        cp      E_NXIO
        jp      nz,t_fail
        ld      b,1
        call    t_status
        jp      c,t_fail
        ld      b,T_SLAVE
        call    t_status
        jp      c,t_fail
    ELSE
        cp      2
        jp      c,t_fail                ; at least two devices
    ENDIF
        call    t_ok

; --- step 3: the volumes -----------------------------------------------
        ld      a,3
        call    t_begin
        ld      a,(K_BLK_NVOL)
        cp      2
        jp      nz,t_fail
        ld      a,(K_BLK_ROOT)
        or      a
        jp      nz,t_fail
        ld      ix,K_VOL
        ld      a,(ix+V_DRV)
        or      (ix+VOL_SIZE+V_DRV)
        jp      nz,t_fail
        ld      a,(ix+V_DEV)
        dec     a
        jp      nz,t_fail
        ld      a,(ix+VOL_SIZE+V_DEV)
        cp      T_SLAVE
        jp      nz,t_fail
        call    t_ok

; --- step 4: 32 sectors written to the slave, read back at 1, 8, 32 ------
        ld      a,4
        call    t_begin
        ld      b,MEM_KERNEL
        k_call  API_MEM_ALLOC
        jp      c,t_fail
        ld      (t_seg),a
        call    t_fill                  ; the pattern into the segment
        ld      a,T_SLAVE
        ld      ixh,0
        ld      ixl,32
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,T_LAST
        ld      de,0
        scf                             ; write
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      c,t_fail
        ld      a,1
        call    t_readback
        jp      c,t_fail
        ld      a,8
        call    t_readback
        jp      c,t_fail
        ld      a,32
        call    t_readback
        jp      c,t_fail
        call    t_ok

; --- step 5: refused ---------------------------------------------------
        ld      a,5
        call    t_begin
        ld      a,1                     ; sectors 4095 and 4096: past the end
        ld      ixh,0
        ld      ixl,2
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,T_TOTAL-1
        ld      de,0
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      nc,t_fail
    IFNDEF M6SD_LEGACY                 ; the adapter maps the Nextor
        cp      E_IO                    ; driver's own code
        jp      nz,t_fail
        ld      a,(K_BLK_LASTERR)       ; the driver's own code: none, the
        or      a                       ; device was not asked
        jp      nz,t_fail
    ENDIF
        ld      a,(t_seg)
        ld      b,a
        ld      c,2                     ; slot 2 + 64 > 64: the kernel's
        ld      hl,0
        ld      de,0
        ld      a,31<<3                 ; volume 0, 32 sectors
        or      a
        k_call  API_BLK_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_INVAL
        jp      nz,t_fail
    IFNDEF M6SD_LEGACY
        ld      a,1                     ; a write to the protected card:
        ld      ixh,0                   ; E_ROFS before the card is asked
        ld      ixl,1
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,0
        ld      de,0
        scf
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_ROFS
        jp      nz,t_fail
        ld      a,(K_BLK_LASTERR)
        or      a
        jp      nz,t_fail
        ld      a,3                     ; a third device: none
        ld      ixh,0
        ld      ixl,1
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,0
        ld      de,0
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_NXIO
        jp      nz,t_fail
        ld      a,(T_REC2+SD_FLAGS_)    ; card 2's slot as init leaves an
        or      2                       ; empty one: no medium, absent;
        ld      (T_REC2+SD_FLAGS_),a    ; status finds the card there now
        xor     a
        ld      (T_REC2),a
        ld      b,T_SLAVE
        ld      d,BQ_STATUS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        cp      DS_CHANGED
        ld      a,0E6h
        jp      nz,t_fail
        ld      b,T_SLAVE               ; SDSC again, the switch off
        ld      c,1
        xor     a
        call    t_private
        jp      c,t_fail
        ld      hl,(T_REC2+SD_TOTAL_)   ; a CMD18 the card ends with a
        inc     hl                      ; data error token: card 2 taken
        inc     hl                      ; as two sectors larger, sectors
        ld      (T_REC2+SD_TOTAL_),hl   ; 4095 and 4096 asked for
        ld      a,T_SLAVE
        ld      ixh,0
        ld      ixl,2
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,T_TOTAL-1
        ld      de,0
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        ld      hl,T_TOTAL
        ld      (T_REC2+SD_TOTAL_),hl
        jp      nc,t_fail
        cp      E_IO
        jp      nz,t_fail
        ld      a,(T_MODE)              ; out of range: the card's token;
        cp      DM_TURBO                ; in Turbo the device's own range
        ld      a,(K_BLK_LASTERR)       ; check answers first, with its code
        jr      z,.range5
        cp      08h
        jr      .judge5
.range5:
        cp      40h|BDE_RANGE
.judge5:
        ld      a,0E7h
        jp      nz,t_fail
        ld      a,T_SLAVE               ; and the card serves the next call
        ld      ixh,0
        ld      ixl,2
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        ld      hl,T_LAST
        ld      de,0
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      c,t_fail
    ENDIF
        call    t_ok

; --- step 6: 64 KB at 1, 8 and 32 sectors per call, against the RTC -------
        ld      a,6
        call    t_begin
        ld      hl,ts_head6
        k_call  API_CON_PUTS
        ld      hl,t_points
.point: ld      a,(hl)
        or      a
        jr      z,.points
        ld      (t_b),a
        push    hl
        call    t_point
        pop     hl
        jp      c,t_fail
        inc     hl
        jr      .point
.points:
        ld      a,6
        ld      (t_step),a
        call    t_ok

; --- step 7: a program reading 64 KB through read() ----------------------
        ld      a,7
        call    t_begin
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,p_rd64
        ld      de,0
        ld      bc,t_fds
        xor     a
        sys     SYS_SPAWNV
        jp      c,t_fail
        ld      b,0
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        push    hl
        call    t_ok
        ld      hl,ts_rd64
        k_call  API_CON_PUTS
        pop     hl
        k_call  API_CON_DEC16
        ld      hl,ts_ticks
        k_call  API_CON_PUTS
        k_call  API_CON_NEWLINE

; --- step 8: Turbo against Standard, the mode switched ---------------------
        ld      a,8
        call    t_begin
    IFNDEF M6SD_LEGACY
        xor     a
        ld      b,1
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        ld      a,(T_PARAMS+DI_CAPS)
        and     DIC_TURBO
        jr      z,.no8
        ld      a,(t_bootmode)          ; the boot's choice: Turbo
        cp      DM_TURBO
        ld      a,0E2h
        jp      nz,t_fail
        ld      a,0                     ; sixteen sectors at slot 0, Turbo
        call    t_read16
        jp      c,t_fail
        ld      a,DM_STANDARD
        call    t_mode
        jp      c,t_fail
        ld      a,32                    ; the same at slot 32, Standard
        call    t_read16
        jp      c,t_fail
        ld      a,DM_TURBO
        call    t_mode
        jp      c,t_fail
        ld      a,(t_seg)
        out     (0FEh),a
        ld      hl,8000h
        ld      de,0A000h
        ld      bc,16*512
.cmp8:  ld      a,(de)
        cp      (hl)
        jr      nz,.differ
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.cmp8
        call    t_page2
        call    t_ok
        ld      hl,ts_turbo_yes
        k_call  API_CON_PUTS
        jr      .step9
.differ:
        call    t_page2
        ld      a,0E3h                  ; Turbo and Standard bytes differ
        jp      t_fail
.no8:   call    t_ok
    ELSE
        call    t_ok
    ENDIF
        ld      hl,ts_turbo_no
        k_call  API_CON_PUTS
.step9:

; --- step 9: the FAT accelerator's two queries -----------------------------
        ld      a,9
        call    t_begin
    IFNDEF M6SD_LEGACY
        xor     a
        ld      b,1
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        ld      a,(T_PARAMS+DI_CAPS)
        and     DIC_FATACC
        jp      z,.noacc
        ; FAT32: entries 2 to 1001.
        ld      a,32
        call    t_table
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        ld      bc,333
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,500
        ld      de,0
        ld      bc,167
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATNEXT
        ld      hl,2
        ld      de,0
        ld      bc,3
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATNEXT
        ld      hl,1000
        ld      de,0
        ld      bc,0
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,1                    ; the span: one sector
        ld      bc,42
        call    t_qis
        jp      c,t_fail
        ; FAT16: entries 2 to 2001.
        ld      a,16
        call    t_table
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        ld      bc,667
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATNEXT
        ld      hl,2000
        ld      de,0
        ld      bc,2001
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,1
        ld      bc,85
        call    t_qis
        jp      c,t_fail
        ; FAT12: entries 2 to 2001, entry 341 across two sectors.
        ld      a,12
        call    t_table
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        ld      bc,667
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,1
        ld      bc,113
        call    t_qis
        jp      c,t_fail
        ld      a,DQ_FATNEXT
        ld      hl,340
        ld      de,0
        ld      bc,342
        call    t_qis
        jp      c,t_fail
        ; Refused: a type that is no FAT's, a cluster below 2, a table
        ; that runs past the device.
        ld      a,13
        ld      (t_qtype),a
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        call    t_fatq
        ld      b,E_INVAL
        call    t_qerr
        jp      c,t_fail
        ld      a,16
        ld      (t_qtype),a
        ld      a,DQ_FATNEXT
        ld      hl,0
        ld      de,0
        call    t_fatq
        ld      b,E_INVAL
        call    t_qerr
        jp      c,t_fail
        ld      hl,T_TOTAL-2
        ld      (t_qfat),hl
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        call    t_fatq
        ld      b,E_IO
        call    t_qerr
        jp      c,t_fail
        call    t_ok
        ld      hl,ts_fatacc_yes
        k_call  API_CON_PUTS
        jr      .pass
.noacc:
    ENDIF
        ; Without the capability — or through the adapter — the queries
        ; answer E_NOSYS.
        ld      a,16
        ld      (t_qtype),a
        ld      hl,T_FATS
        ld      (t_qfat),hl
        ld      a,DQ_FATCOUNT
        ld      hl,2
        ld      de,0
        call    t_fatq
        ld      b,E_NOSYS
        call    t_qerr
        jp      c,t_fail
        call    t_ok
        ld      hl,ts_fatacc_no
        k_call  API_CON_PUTS
.pass:  ld      hl,ts_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
t_halt: ei
        halt
        jr      t_halt

; t_table — A = the type, 12, 16 or 32: the 8 sectors of a table of
; that type with 2000 data clusters (1000 for FAT32), every entry c
; free when c mod 3 = 0 and marked otherwise (FFFh, FFFFh, F0000001h —
; a FAT32 entry's top four bits set either way, to be ignored), built
; in the test's segment and written to card 2's sectors T_FATS up;
; t_qfat and t_qtype set for the queries. CF when the write failed.
; Corrupts everything.
t_table:
        ld      (t_qtype),a
        ld      hl,T_FATS
        ld      (t_qfat),hl
        ld      a,(t_seg)
        out     (0FEh),a
        ld      hl,8000h
        ld      de,8001h
        ld      bc,4095
        ld      (hl),0
        ldir
        ld      hl,0
        ld      (t_c),hl
        xor     a
        ld      (t_mod3),a
.entry: ld      a,(t_mod3)
        or      a
        ld      a,0                     ; free: 00
        jr      z,.v
        dec     a                       ; marked: FF
.v:     ld      (t_v),a
        ld      a,(t_qtype)
        cp      32
        jr      z,.e32
        cp      16
        jr      z,.e16
        ld      hl,(t_c)                ; FAT12: byte c + c/2 up
        ld      d,h
        ld      e,l
        srl     d
        rr      e
        add     hl,de
        ld      de,8000h
        add     hl,de
        ld      a,(t_c)
        rra
        ld      a,(t_v)
        jr      c,.odd
        ld      (hl),a                  ; even: the whole byte, then the
        inc     hl                      ;   low nibble of the next
        and     0Fh
        ld      b,a
        ld      a,(hl)
        and     0F0h
        or      b
        ld      (hl),a
        jr      .step
.odd:   and     0F0h                    ; odd: the high nibble of the
        ld      b,a                     ;   byte, then the whole next
        ld      a,(hl)
        and     0Fh
        or      b
        ld      (hl),a
        inc     hl
        ld      a,(t_v)
        ld      (hl),a
        jr      .step
.e16:   ld      hl,(t_c)
        add     hl,hl
        ld      de,8000h
        add     hl,de
        ld      a,(t_v)
        ld      (hl),a
        inc     hl
        ld      (hl),a
        jr      .step
.e32:   ld      hl,(t_c)
        add     hl,hl
        add     hl,hl
        ld      de,8000h
        add     hl,de
        ld      a,(t_v)
        and     1
        ld      (hl),a
        inc     hl
        ld      (hl),0
        inc     hl
        ld      (hl),0
        inc     hl
        ld      (hl),0F0h
.step:  ld      a,(t_mod3)
        inc     a
        cp      3
        jr      nz,.m3
        xor     a
.m3:    ld      (t_mod3),a
        ld      hl,(t_c)
        inc     hl
        ld      (t_c),hl
        ld      de,2002                 ; N + 2: past the last entry
        ld      a,(t_qtype)
        cp      32
        jr      nz,.last
        ld      de,1002
.last:  or      a
        sbc     hl,de
        jp      nz,.entry
        call    t_page2
        ld      a,(t_seg)
        ld      b,a
        ld      c,0
        ld      ixh,0
        ld      ixl,8
        ld      hl,T_FATS
        ld      de,0
        ld      a,T_SLAVE
        scf                             ; write
        k_call  API_BLK_DEV_RW
        jp      t_page2

; t_fatq — A = the query, HL = the starting cluster, DE = the span: the
; block built in T_PARAMS from t_qfat and t_qtype (8 sectors; 2000 data
; clusters, 1000 for FAT32) and the driver asked for card 2. Out as the
; driver answers: DE:HL, or CF and A = the errno. Corrupts everything.
t_fatq:
        ld      (t_qq),a
        ld      (t_qx),hl
        ld      (t_qspan),de
        ld      hl,T_PARAMS
        ld      de,T_PARAMS+1
        ld      bc,BP_SIZE-1
        ld      (hl),0
        ldir
        ld      hl,(t_qfat)
        ld      (T_PARAMS+BP_FAT),hl
        ld      a,8
        ld      (T_PARAMS+BP_FATSZ),a
        ld      a,(t_qtype)
        ld      (T_PARAMS+BP_TYPE),a
        ld      hl,2000
        cp      32
        jr      nz,.n
        ld      hl,1000
.n:     ld      (T_PARAMS+BP_NCLUS),hl
        ld      hl,(t_qx)
        ld      (T_PARAMS+BP_START),hl
        ld      hl,(t_qspan)
        ld      (T_PARAMS+BP_SPAN),hl
        ld      a,(t_qq)
        ld      e,a
        xor     a
        ld      b,T_SLAVE
        ld      d,BQ_QUERY
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        jp      t_page2

; t_qis — t_fatq with BC = the answer expected. CF with A = a code when
; the driver failed or answered otherwise.
t_qis:  push    bc
        call    t_fatq
        ld      (t_qcode),bc            ; the device's code, on a failure
        pop     bc
        jr      nc,.answered
        k_call  API_CON_HEX8            ; the errno and the device's code:
        ld      a,' '                   ;   the step's evidence
        k_call  API_CON_PUTC
        ld      a,(t_qcode+1)
        k_call  API_CON_HEX8
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,0EDh                  ; the query failed
        scf
        ret
.answered:
        ld      a,d
        or      e
        jr      nz,.no
        or      a
        sbc     hl,bc
        jr      nz,.no
        ret
.no:    ld      a,0EEh                  ; the answer differs
        scf
        ret

; t_qerr — after t_fatq, B = the errno expected: CF with A = a code
; when the driver answered, or with another errno.
t_qerr: jr      nc,.answered
        cp      b
        ret     z
        ld      a,0EFh                  ; another errno
        scf
        ret
.answered:
        ld      a,0F0h                  ; answered where it should refuse
        scf
        ret

; t_mode — A = the mode asked of the driver through DQ_MODE; the mode
; in force must be it. CF otherwise. Corrupts everything.
t_mode:
        ld      (T_PARAMS),a
        xor     a
        ld      b,1
        ld      d,BQ_QUERY
        ld      e,DQ_MODE
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        ret     c
        ld      a,(T_PARAMS+1)
        ld      hl,T_PARAMS
        cp      (hl)
        ld      a,0E2h                  ; the mode in force differs
        scf
        ret     nz
        or      a
        ret

; t_read16 — A = the slot: the slave's last sixteen sectors read into
; the test's segment from that slot, one call. CF when it failed.
t_read16:
        ld      c,a
        ld      a,T_SLAVE
        ld      ixh,0
        ld      ixl,16
        ld      hl,t_seg
        ld      b,(hl)
        ld      hl,T_LAST
        ld      de,0
        or      a
        k_call  API_BLK_DEV_RW
        jp      t_page2

; t_info — B = device, C = its flags, DE -> its name's 14 bytes: the
; record through BQ_INFO, checked: the flags, count T_TOTAL, the name,
; the identity's device and unit. CF when a check fails (A = a code).
; Corrupts everything.
t_info:
        ld      a,b
        ld      (t_dev),a
        ld      a,c
        ld      (t_flags),a
        ld      (t_name),de
        xor     a
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        ret     c
        ld      a,(T_PARAMS+DI_FLAGS)
        ld      hl,t_flags
        cp      (hl)
        jr      nz,.bad
        ld      hl,(T_PARAMS+DI_COUNT)
        ld      de,T_TOTAL
        or      a
        sbc     hl,de
        jr      nz,.count
        ld      hl,(T_PARAMS+DI_COUNT+2)
        ld      a,h
        or      l
        jr      nz,.count
        ld      hl,T_PARAMS+DI_NAME
        ld      de,(t_name)
        ld      b,14
.name:  ld      a,(de)
        cp      (hl)
        jr      nz,.named
        inc     hl
        inc     de
        djnz    .name
        ld      a,(T_PARAMS+DI_IDENT+1)
        ld      hl,t_dev
        cp      (hl)
        jr      nz,.ident
        ld      a,(T_PARAMS+DI_IDENT+2)
        dec     a
        jr      nz,.ident
        or      a
        ret
.bad:   ld      a,0E4h                  ; the flags
        scf
        ret
.count: ld      a,0EAh                  ; the count
        scf
        ret
.named: ld      a,0EBh                  ; the name
        scf
        ret
.ident: ld      a,0ECh                  ; the identity
        scf
        ret

; t_private — B = device, C = its state in the driver's own record (1
; SDSC, 2 SDHC), A = the write-protect bit expected in its flags (0 or
; 4): the record through the driver's private query, checked. CF when
; a check fails.
t_private:
        ld      (t_flags),a
        ld      a,c
        ld      (t_dev),a
        xor     a
        ld      d,BQ_QUERY
        ld      e,DQ_PRIVATE
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        ret     c
        ld      a,(T_PARAMS)            ; the state
        ld      hl,t_dev
        cp      (hl)
        jr      nz,.bad
        ld      a,(T_PARAMS+1)          ; the flags: the switch's bit
        and     4
        ld      hl,t_flags
        cp      (hl)
        jr      nz,.bad
        or      a
        ret
.bad:   ld      a,0E9h
        scf
        ret

; t_status — B = device: DS_SAME expected. CF otherwise.
t_status:
        xor     a
        ld      d,BQ_STATUS
        k_call  API_BLK_QUERY
        call    t_page2
        ret     c
        cp      DS_SAME
        ld      a,0E5h
        scf
        ret     nz
        or      a
        ret

; t_fill — the pattern of sectors T_LAST to T_LAST + 31 into the test's
; segment: byte i of sector n is the low byte of 7 n + i, xor 55h in the
; sector's second half. Corrupts everything.
t_fill:
        ld      a,(t_seg)
        out     (0FEh),a
        ld      hl,8000h
        ld      c,low T_LAST
        ld      b,32
.sector:
        push    bc
        ld      a,c
        ld      d,a
        add     a,a
        add     a,a
        add     a,a
        sub     d                       ; 7 n, low byte
        ld      d,a
        ld      e,0
.lo:    ld      a,d
        add     a,e
        ld      (hl),a
        inc     hl
        inc     e
        jr      nz,.lo
.hi:    ld      a,d
        add     a,e
        xor     55h
        ld      (hl),a
        inc     hl
        inc     e
        jr      nz,.hi
        pop     bc
        inc     c
        djnz    .sector
        jp      t_page2

; t_readback — A = sectors per call: the segment cleared, the slave's
; last 32 sectors read into it A per call, every byte compared with the
; pattern. CF when a call failed or a byte differs. Corrupts everything.
t_readback:
        ld      (t_rn),a
        ld      a,(t_seg)
        out     (0FEh),a
        ld      hl,8000h
        ld      de,8001h
        ld      bc,3FFFh
        ld      (hl),0
        ldir
        call    t_page2
        xor     a
        ld      (t_slot),a
        ld      hl,T_LAST
        ld      (t_rsec),hl
.call:  ld      a,(t_rn)
        ld      ixl,a
        ld      ixh,0
        ld      a,(t_slot)
        ld      c,a
        ld      a,(t_seg)
        ld      b,a
        ld      hl,(t_rsec)
        ld      de,0
        ld      a,T_SLAVE
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        ret     c
        ld      a,(t_rn)
        ld      hl,(t_rsec)
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      (t_rsec),hl
        add     a,a                     ; two slots a sector
        ld      hl,t_slot
        add     a,(hl)
        ld      (hl),a
        cp      64
        jr      c,.call
        ; Every byte against the pattern.
        ld      a,(t_seg)
        out     (0FEh),a
        ld      hl,8000h
        ld      c,low T_LAST
        ld      b,32
.sector:
        push    bc
        ld      a,c
        ld      d,a
        add     a,a
        add     a,a
        add     a,a
        sub     d
        ld      d,a
        ld      e,0
.lo:    ld      a,d
        add     a,e
        cp      (hl)
        jr      nz,.bad
        inc     hl
        inc     e
        jr      nz,.lo
.hi:    ld      a,d
        add     a,e
        xor     55h
        cp      (hl)
        jr      nz,.bad
        inc     hl
        inc     e
        jr      nz,.hi
        pop     bc
        inc     c
        djnz    .sector
        call    t_page2
        or      a
        ret
.bad:   pop     bc
        call    t_page2
        ld      a,0E1h                  ; a byte differs
        scf
        ret

; t_point — (t_b) sectors per call: T_SECTORS sectors of device 1 read
; from its first sectors, every call into slot 0 of the test's segment.
; The RTC's seconds digit is polled tight for a change before the first
; call and after the last, K_TICKS noted at each, and watched between
; calls to count the changes in the window; after the last call the
; window runs to the next change, and on until two whole seconds at
; least. Sampled between calls instead, an edge would be seen up to a
; call late — 5 ticks at 32 sectors a call. The line: B, calls, ticks,
; ms per call, ms per sector, the clock's whole seconds, the ticks
; counted over them, lost. CF when a call failed, when the clock did not
; advance, or — not under M6SD_LEGACY — when more than T_TOL ticks were
; lost or more than one tick over 60 n counted. Corrupts everything.
t_point:
        ld      a,13                    ; RTC mode register: block 0
        out     (0B4h),a
        ld      a,08h
        out     (0B5h),a
        call    t_rtc_sec
        ld      (t_rtc_prev),a
        call    t_rtc_edge
        jp      c,.nortc
        ld      (t_rtc_first),hl
        xor     a
        ld      (t_rtc_n),a
        ld      (t_over),a
        ld      hl,T_SECTORS
        ld      a,(t_b)
.div:   srl     a
        jr      c,.n
        srl     h
        rr      l
        jr      .div
.n:     ld      (t_calls),hl
        ld      hl,0
        ld      (t_rsec),hl
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,(t_calls)
.loop:  ld      (t_i),hl
        call    t_rtc_watch
        ld      a,(t_b)
        ld      ixl,a
        ld      ixh,0
        ld      a,(t_seg)
        ld      b,a
        ld      c,0
        ld      hl,(t_rsec)
        ld      de,0
        ld      a,1
        or      a
        k_call  API_BLK_DEV_RW
        call    t_page2
        ret     c
        ld      a,(t_b)
        ld      hl,(t_rsec)
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      a,h
        and     3                       ; mod 1024: the first 512 KB
        ld      h,a
        ld      (t_rsec),hl
        ld      hl,(t_i)
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_ticks),hl
        call    t_rtc_watch             ; a change during the last call:
                                        ; counted, never taken as an edge
.tail:  call    t_rtc_edge              ; the window's last change
        jp      c,.nortc
        ld      (t_rtc_last),hl
        ld      hl,t_rtc_n
        inc     (hl)
        ld      a,(hl)
        cp      2
        jr      c,.tail
        ; The line.
        ld      hl,ts_b
        k_call  API_CON_PUTS
        ld      a,(t_b)
        call    k_dec8
        ld      hl,ts_calls
        k_call  API_CON_PUTS
        ld      hl,(t_calls)
        k_call  API_CON_DEC16
        ld      hl,ts_ticks2
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        k_call  API_CON_DEC16
        ld      hl,ts_call
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        ld      de,1667                 ; hundredths of a ms per tick
        ld      bc,(t_calls)
        call    k_muldiv
        call    k_hundredths
        ld      hl,ts_sector
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        ld      de,1667
        ld      bc,T_SECTORS
        call    k_muldiv
        call    k_hundredths
        ld      hl,ts_rtc
        k_call  API_CON_PUTS
        ld      a,(t_rtc_n)                 ; changes after the first: seconds
        call    k_dec8
        ld      hl,ts_counted
        k_call  API_CON_PUTS
        ld      hl,(t_rtc_last)
        ld      de,(t_rtc_first)
        or      a
        sbc     hl,de
        push    hl
        k_call  API_CON_DEC16
        ld      hl,ts_lost
        k_call  API_CON_PUTS
        ld      a,(t_rtc_n)
        ld      d,0
        ld      e,a
        ld      hl,0
        ld      b,60
.x60:   add     hl,de
        djnz    .x60                    ; hl = 60 n, expected
        pop     de                      ; counted
        or      a
        sbc     hl,de                   ; expected - counted = lost
        jp      p,.lost
        inc     hl
        ld      a,h
        ld      (t_over),a              ; FFh: counted more than 60 n + 1
        ld      hl,0                    ; more than expected: none lost
.lost:  ld      (t_lost),hl
        k_call  API_CON_DEC16
        k_call  API_CON_NEWLINE
    IFDEF M6SD_LEGACY
        or      a
        ret
    ELSE
        ld      a,(t_over)
        or      a
        ld      a,0E8h                  ; more ticks than the clock allows
        scf
        ret     nz
        ld      hl,(t_lost)
        ld      de,T_TOL+1
        or      a
        sbc     hl,de
        ld      a,0E6h                  ; ticks were lost
        ccf
        ret
    ENDIF
.nortc: ld      hl,ts_nortc
        k_call  API_CON_PUTS
        k_call  API_CON_NEWLINE
        ld      a,0E7h                  ; the clock did not advance
        scf
        ret

; t_rtc_sec — A = the RTC's seconds digit. t_rtc_watch — the digit
; compared with the last one seen; at a change, counted. t_rtc_edge —
; the digit polled until it changes: HL = K_TICKS then; CF when 150
; ticks pass without a change.
t_rtc_sec:
        xor     a
        out     (0B4h),a
        in      a,(0B5h)
        and     0Fh
        ret
t_rtc_watch:
        call    t_rtc_sec
        ld      b,a
        ld      a,(t_rtc_prev)
        cp      b
        ret     z
        ld      a,b
        ld      (t_rtc_prev),a
        ld      hl,t_rtc_n
        inc     (hl)
        ret
t_rtc_edge:
        ld      hl,(K_TICKS)
        ld      (t_rtc_t),hl
.spin:  call    t_rtc_sec
        ld      b,a
        ld      a,(t_rtc_prev)
        cp      b
        jr      nz,.got
        ld      hl,(K_TICKS)
        ld      de,(t_rtc_t)
        or      a
        sbc     hl,de
        ld      de,150
        sbc     hl,de
        jr      c,.spin
        scf                             ; 150 ticks and no change
        ret
.got:   ld      a,b
        ld      (t_rtc_prev),a
        ld      hl,(K_TICKS)
        or      a
        ret

; t_page2 — the test's page 2 back: the block layer leaves the window
; there. Preserves AF, HL.
t_page2:
        push    af
        ld      a,(K_MAP+2)
        out     (0FEh),a
        pop     af
        ret

; t_begin — A = the step: recorded, its number printed.
t_begin:
        ld      (t_step),a
        k_call  API_CON_NEWLINE
        ld      a,(t_step)
        call    k_dec8
        ld      a,' '
        k_call  API_CON_PUTC
        ret
t_ok:   ld      hl,ts_ok
        k_call  API_CON_PUTS
        ret

; t_fail — A = a code; t_fail_status — A = a status: the line, the verdict.
t_fail_status:
        ld      hl,ts_status
        k_call  API_CON_PUTS
        jr      t_fail1
t_fail:
        push    af
        ld      hl,ts_fail
        k_call  API_CON_PUTS
        pop     af
t_fail1:
        push    af
        ld      a,(t_step)
        call    k_dec8
        ld      hl,ts_code
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jp      t_halt

        include "m6util.asm"

ts_name1:   db  "enMSX 0.1 SDHC"       ; the card's CID, and its class
ts_name2:   db  "enMSX 0.1 SDSC"
ts_ok:      db  "ok",0
ts_head6:   db  "64 KB per point, 8 times, against the rtc",10,0
ts_b:       db  "B=",0
ts_calls:   db  " calls ",0
ts_ticks2:  db  " ticks ",0
ts_call:    db  " call ",0
ts_sector:  db  " ms sector ",0
ts_rtc:     db  " ms rtc ",0
ts_counted: db  " s counted ",0
ts_lost:    db  " lost ",0
ts_nortc:   db  "the clock did not advance",0
ts_rd64:    db  ", rd64 ",0
ts_turbo_yes: db " turbo: yes",10,0
ts_turbo_no: db  " turbo: no",10,0
ts_fatacc_yes: db " fatacc: yes",10,0
ts_fatacc_no: db " fatacc: no",10,0
ts_ticks:   db  " ticks",0
ts_fail:    db  10,"FAIL step ",0
ts_status:  db  10,"FAIL status step ",0
ts_code:    db  " code ",0
ts_pass:    db  "PASS",10,0
p_rd64:     db  "/RD64",0
t_fds:      db  0FFh,0FFh,0FFh
t_step:     db  0
t_bootmode: db  0
t_seg:      db  0
t_dev:      db  0
t_flags:    db  0
t_name:     dw  0
t_rn:       db  0
t_slot:     db  0
t_b:        db  0
t_points:   db  1,8,32,0
t_rsec:     dw  0
t_calls:    dw  0
t_i:        dw  0
t_t0:       dw  0
t_ticks:    dw  0
t_lost:     dw  0
t_over:     db  0
t_rtc_prev: db  0
t_rtc_n:    db  0
t_rtc_first: dw 0
t_rtc_last: dw  0
t_rtc_t:    dw  0
t_qcode:    dw  0
t_qtype:    db  0
t_qq:       db  0
t_qx:       dw  0
t_qspan:    dw  0
t_qfat:     dw  0
t_c:        dw  0
t_mod3:     db  0
t_v:        db  0
tb_end:
