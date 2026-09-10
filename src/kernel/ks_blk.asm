; The block layer's cold half, in the switched part: the enumeration of
; drivers, devices, LUNs and partitions into the volume table, the boot
; listing, the buffer cache and the RTC read. Runs under the window (this
; image in page 2) and the storage gate (the storage segment in page 1),
; and calls the resident through the jump table only. Keeps no variable
; of its own — the image may be a ROM bank — and writes only to the
; storage segment, at SG+offset, where ST_VARS holds what it has to
; remember.

SG              equ 4000h               ; the storage segment, from here
SG_INFO         equ SG+ST_INFO
SG_HDR          equ SG+ST_HDR
SG_BUF          equ SG+ST_BUF
SG_SCRATCH      equ SG_BUF+BUF_SCRATCH*512 ; where blk_dev_rw reads to
SLOT_BUF0       equ ST_BUF/512          ; the slot of buffer 0
MBR_TABLE       equ 1BEh                ; the partition table in an MBR/EBR
PE_TYPE         equ 4                   ; a partition entry: the type byte
PE_FIRST        equ 8                   ; 4: first sector, relative
PE_COUNT        equ 12                  ; 4: sectors
PT_EXTENDED     equ 05h

; ---------------------------------------------------------------------
; The enumeration

; ks_blk_init — every driver in the record, every device and LUN it has,
; every partition of each: the volume table, the boot volume and the
; listing. Corrupts everything.
ks_blk_init:
        xor     a
        ld      (K_BLK_NVOL),a
        ld      (SG+SV_FULL),a
        ld      a,VOL_NONE
        ld      (K_BLK_ROOT),a
        ld      a,(K_REC+KR_NDRV)
        or      a
        jr      nz,.some
        ld      hl,s_nodriver
        k_call  API_CON_PUTS
        ret
.some:  cp      5
        jr      c,.count
        ld      a,4
.count: ld      (SG+SV_NDRV),a
        xor     a
        ld      (SG+SV_DRV),a
.driver:
        call    bi_name                 ; the driver's name into SV_NAME
        ld      a,1
        ld      (SG+SV_DEV),a
.device:
        ld      a,(SG+SV_DEV)
        ld      b,a
        ld      c,0
        ld      d,BQ_DEVINFO
        ld      a,(SG+SV_DRV)
        k_call  API_BLK_QUERY
        jr      c,.nextdev              ; no such device
        ld      a,(SG_INFO+0)           ; LUNs, 1-8; 1 when none
        or      a
        jr      nz,.luns
        inc     a
.luns:  cp      8
        jr      c,.nlun
        ld      a,7
.nlun:  ld      (SG+SV_NLUN),a
        xor     a
        ld      (SG+SV_NDEV),a
        ld      a,1
        ld      (SG+SV_LUN),a
.lun:   call    bi_lun
        ld      a,(SG+SV_LUN)
        inc     a
        ld      (SG+SV_LUN),a
        ld      hl,SG+SV_NLUN
        cp      (hl)
        jr      z,.lun
        jr      c,.lun
        ld      a,(SG+SV_NDEV)
        or      a
        jr      nz,.nextdev
        call    bi_devlun               ; "  d.l"
        ld      hl,s_novolumes
        k_call  API_CON_PUTS
.nextdev:
        ld      a,(SG+SV_DEV)
        inc     a
        ld      (SG+SV_DEV),a
        cp      8
        jr      c,.device
        ld      a,(SG+SV_DRV)
        inc     a
        ld      (SG+SV_DRV),a
        ld      hl,SG+SV_NDRV
        cp      (hl)
        jr      c,.driver
        ret

; bi_name — the driver's DRV_NAME into SV_NAME, its length without the
; trailing spaces into SV_NAMELEN.
bi_name:
        ld      a,(SG+SV_DRV)
        ld      d,BQ_DRVNAME
        k_call  API_BLK_QUERY
        ld      hl,SG_INFO
        ld      de,SG+SV_NAME
        ld      bc,32
        ldir
        ld      hl,SG+SV_NAME+31
        ld      b,32
.trim:  ld      a,(hl)
        cp      ' '
        jr      nz,.len
        dec     hl
        djnz    .trim
.len:   ld      a,b
        ld      (SG+SV_NAMELEN),a
        ret

; bi_lun — one LUN of the current device: LUN_INFO, then its partitions.
bi_lun:
        ld      a,(SG+SV_DRV)
        push    af
        ld      a,(SG+SV_DEV)
        ld      b,a
        ld      a,(SG+SV_LUN)
        ld      c,a
        pop     af
        ld      d,BQ_LUNINFO
        k_call  API_BLK_QUERY
        ret     c                       ; not there
        ld      a,(SG_INFO+0)           ; medium type: 0 = block device
        or      a
        ret     nz
        ld      hl,(SG_INFO+1)          ; sector size
        ld      de,512
        or      a
        sbc     hl,de
        ret     nz
        ld      a,(SG_INFO+7)           ; flags
        bit     3,a
        jr      z,.automap
        call    bi_devlun
        ld      hl,s_noautomap
        k_call  API_CON_PUTS
        ret
.automap:
        and     VF_REMOVABLE|VF_RO
        ld      (SG+SV_LFLAGS),a
        ld      hl,SG_INFO+3            ; total sectors
        ld      de,SG+SV_TOTAL
        ld      bc,4
        ldir
        ; fall through

; bi_walk — the partitions of the current LUN: sector 0, the four primary
; entries in order (a type 05h one opens its chain), then sector 0 itself
; as a FAT volume when nothing was found.
bi_walk:
        xor     a
        ld      (SG+SV_FOUND),a
        ld      hl,0
        ld      de,0
        call    bi_read
        jr      nc,.have0
        call    bi_devlun
        ld      hl,s_unreadable
        k_call  API_CON_PUTS
        ret
.have0: ld      hl,SG_SCRATCH+MBR_TABLE ; the four entries, kept aside
        ld      de,SG_INFO
        ld      bc,64
        ldir
        ld      a,1
        ld      (SG+SV_PRI),a
.pri:   ld      a,(SG+SV_PRI)
        dec     a
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; (pri - 1) * 16
        ld      e,a
        ld      d,0
        ld      ix,SG_INFO
        add     ix,de
        ld      a,(ix+PE_TYPE)
        cp      PT_EXTENDED
        jr      nz,.primary
        call    bi_chain
        jr      .nextpri
.primary:
        ld      hl,0                    ; base 0: the MBR's own numbers
        ld      (SG+SV_EBR),hl
        ld      (SG+SV_EBR+2),hl
        ld      a,PK_PRIMARY
        ld      (SG+SV_PKIND),a
        call    bi_candidate
.nextpri:
        ld      a,(SG+SV_PRI)
        inc     a
        ld      (SG+SV_PRI),a
        cp      5
        jr      c,.pri
        ; Nothing on the table: sector 0 as a volume.
        ld      a,(SG+SV_FOUND)
        or      a
        ret     nz
        ld      hl,0
        ld      de,0
        call    bi_read
        ret     c
        call    bi_bpb
        ret     nz                      ; not a FAT boot sector either
        ld      hl,0
        ld      (SG+SV_CAND),hl
        ld      (SG+SV_CAND+2),hl
        ld      (SG+SV_CCOUNT+2),hl
        ld      hl,(SG_SCRATCH+13h)     ; total sectors, 16 bits
        ld      a,h
        or      l
        jr      nz,.total
        ld      hl,(SG_SCRATCH+20h)     ; or 32
        ld      de,(SG_SCRATCH+22h)
        ld      (SG+SV_CCOUNT+2),de
.total: ld      (SG+SV_CCOUNT),hl
        xor     a
        ld      (SG+SV_CTYPE),a
        ld      a,PK_SUPER
        ld      (SG+SV_PKIND),a
        jp      bi_row

; bi_chain — IX -> a type 05h entry of the MBR: walk its EBRs. Each EBR's
; entry 1 is a volume relative to the EBR, its entry 2 the next EBR
; relative to the chain's start, type 05h, or nothing.
bi_chain:
        ld      l,(ix+PE_FIRST)
        ld      h,(ix+PE_FIRST+1)
        ld      (SG+SV_EXT),hl
        ld      (SG+SV_EBR),hl
        ld      e,(ix+PE_FIRST+2)
        ld      d,(ix+PE_FIRST+3)
        ld      (SG+SV_EXT+2),de
        ld      (SG+SV_EBR+2),de
        ld      c,(ix+PE_COUNT)
        ld      b,(ix+PE_COUNT+1)
        add     hl,bc
        ld      (SG+SV_EXTEND),hl
        ld      c,(ix+PE_COUNT+2)
        ld      b,(ix+PE_COUNT+3)
        ex      de,hl
        adc     hl,bc
        ld      (SG+SV_EXTEND+2),hl
        xor     a
        ld      (SG+SV_NLOG),a
.ebr:   ld      hl,(SG+SV_EBR)
        ld      de,(SG+SV_EBR+2)
        call    bi_read
        jr      nc,.have
        call    bi_devlun
        ld      hl,s_badchain
        k_call  API_CON_PUTS
        ret
.have:  ld      ix,SG_SCRATCH+MBR_TABLE+16 ; entry 2: the link, kept aside
        ld      a,(ix+PE_TYPE)
        ld      (SG+SV_LTYPE),a
        ld      l,(ix+PE_FIRST)
        ld      h,(ix+PE_FIRST+1)
        ld      (SG+SV_LINK),hl
        ld      l,(ix+PE_FIRST+2)
        ld      h,(ix+PE_FIRST+3)
        ld      (SG+SV_LINK+2),hl
        ld      a,(SG+SV_NLOG)
        inc     a
        ld      (SG+SV_NLOG),a
        ld      a,PK_LOGICAL
        ld      (SG+SV_PKIND),a
        ld      ix,SG_SCRATCH+MBR_TABLE ; entry 1: the volume
        call    bi_candidate
        ld      a,(SG+SV_LTYPE)
        cp      PT_EXTENDED
        ret     nz                      ; the chain ends here
        ld      a,(SG+SV_NLOG)
        cp      9
        jr      c,.link
        call    bi_devlun
        ld      hl,s_morelogical
        k_call  API_CON_PUTS
        ret
.link:  ; next = ext + link; must be above this EBR and below the end.
        ld      hl,(SG+SV_EXT)
        ld      de,(SG+SV_LINK)
        add     hl,de
        ex      de,hl                   ; de = next.lo
        ld      hl,(SG+SV_EXT+2)
        ld      bc,(SG+SV_LINK+2)
        adc     hl,bc                   ; hl = next.hi
        jr      c,.bad
        push    hl
        push    de
        ld      bc,(SG+SV_EBR+2)
        or      a
        sbc     hl,bc                   ; next.hi - ebr.hi
        jr      c,.badpop
        jr      nz,.above
        ex      de,hl
        ld      bc,(SG+SV_EBR)
        or      a
        sbc     hl,bc                   ; next.lo - ebr.lo
        jr      c,.badpop
        jr      z,.badpop               ; the same sector again
.above: pop     de
        pop     hl
        push    hl
        push    de
        ld      bc,(SG+SV_EXTEND+2)
        ex      de,hl                   ; hl = next.lo, de = next.hi
        push    hl
        ex      de,hl                   ; hl = next.hi
        or      a
        sbc     hl,bc                   ; next.hi - end.hi
        pop     hl
        jr      c,.inside
        jr      nz,.badpop
        ld      bc,(SG+SV_EXTEND)
        or      a
        sbc     hl,bc                   ; next.lo - end.lo
        jr      nc,.badpop
.inside:
        pop     de
        pop     hl
        ld      (SG+SV_EBR),de
        ld      (SG+SV_EBR+2),hl
        jp      .ebr
.badpop:
        pop     de
        pop     hl
.bad:   call    bi_devlun
        ld      hl,s_badchain
        k_call  API_CON_PUTS
        ret

; bi_candidate — IX -> a partition entry, SV_EBR = the base its first
; sector is relative to, SV_PKIND set: a row of the volume table when the
; type is one of ours, the numbers are sane, and its boot sector is a FAT
; volume's. Corrupts everything.
bi_candidate:
        ld      a,(ix+PE_TYPE)
        ld      (SG+SV_CTYPE),a
        cp      01h
        jr      z,.type
        cp      04h
        jr      z,.type
        cp      06h
        jr      z,.type
        cp      0Eh
        ret     nz
.type:  ld      l,(ix+PE_FIRST)
        ld      h,(ix+PE_FIRST+1)
        ld      e,(ix+PE_FIRST+2)
        ld      d,(ix+PE_FIRST+3)
        ld      a,h
        or      l
        or      d
        or      e
        ret     z                       ; first = 0
        ld      bc,(SG+SV_EBR)
        add     hl,bc
        ld      (SG+SV_CAND),hl
        ld      bc,(SG+SV_EBR+2)
        ex      de,hl
        adc     hl,bc
        ld      (SG+SV_CAND+2),hl
        ld      l,(ix+PE_COUNT)
        ld      h,(ix+PE_COUNT+1)
        ld      e,(ix+PE_COUNT+2)
        ld      d,(ix+PE_COUNT+3)
        ld      (SG+SV_CCOUNT),hl
        ld      (SG+SV_CCOUNT+2),de
        ld      a,h
        or      l
        or      d
        or      e
        ret     z                       ; count = 0
        ; With the LUN's size known: first + count <= total.
        ld      hl,(SG+SV_TOTAL)
        ld      de,(SG+SV_TOTAL+2)
        ld      a,h
        or      l
        or      d
        or      e
        jr      z,.sane
        ld      hl,(SG+SV_CAND)
        ld      bc,(SG+SV_CCOUNT)
        add     hl,bc
        ex      de,hl                   ; de = end.lo
        ld      hl,(SG+SV_CAND+2)
        ld      bc,(SG+SV_CCOUNT+2)
        adc     hl,bc                   ; hl = end.hi
        ret     c                       ; past 32 bits
        ld      bc,(SG+SV_TOTAL+2)
        push    hl
        or      a
        sbc     hl,bc                   ; end.hi - total.hi
        pop     hl
        jr      c,.sane                 ; end.hi < total.hi
        ret     nz                      ; end.hi > total.hi
        ex      de,hl                   ; equal: the low words decide
        ld      bc,(SG+SV_TOTAL)
        or      a
        sbc     hl,bc                   ; end.lo - total.lo
        jr      c,.sane
        ret     nz                      ; end.lo > total.lo
.sane:  ld      hl,(SG+SV_CAND)
        ld      de,(SG+SV_CAND+2)
        call    bi_read
        jr      nc,.boot
        call    bi_devlun
        call    bi_plabel
        ld      hl,s_unreadable
        k_call  API_CON_PUTS
        ret
.boot:  call    bi_bpb
        jr      z,bi_row
        call    bi_devlun
        call    bi_plabel
        ld      hl,s_badboot
        k_call  API_CON_PUTS
        ret

; bi_row — the candidate in SV_CAND/SV_CCOUNT/SV_CTYPE/SV_PKIND becomes a
; row of the volume table, the boot volume if it is, and a line.
bi_row:
        ld      a,(K_BLK_NVOL)
        cp      VOL_N
        jr      c,.room
        ld      a,(SG+SV_FULL)
        or      a
        ret     nz
        inc     a
        ld      (SG+SV_FULL),a
        ld      hl,s_morevolumes
        k_call  API_CON_PUTS
        ret
.room:  push    af                      ; the row's index
        ld      e,a
        add     a,a
        add     a,e
        add     a,a
        add     a,a                     ; * 12
        ld      e,a
        ld      d,0
        ld      ix,K_VOL
        add     ix,de
        ld      a,(SG+SV_DRV)
        ld      (ix+V_DRV),a
        ld      a,(SG+SV_DEV)
        ld      (ix+V_DEV),a
        ld      a,(SG+SV_LUN)
        ld      (ix+V_LUN),a
        ld      a,(SG+SV_LFLAGS)
        ld      (ix+V_FLAGS),a
        push    ix
        pop     de
        ld      hl,V_FIRST
        add     hl,de
        ex      de,hl
        ld      hl,SG+SV_CAND           ; SV_CAND then SV_CCOUNT: 8 bytes
        ld      bc,8
        ldir
        pop     af
        push    af
        inc     a
        ld      (K_BLK_NVOL),a
        ld      hl,SG+SV_FOUND
        inc     (hl)
        ld      hl,SG+SV_NDEV
        inc     (hl)
        ; The boot volume: the record's driver, device, LUN and first sector.
        ld      a,(SG+SV_DRV)
        add     a,a
        add     a,KR_DRVS
        ld      e,a
        ld      d,0
        ld      hl,K_REC
        add     hl,de
        ld      a,(K_REC+KR_DRV+NXD_SLOT)
        cp      (hl)
        jr      nz,.notroot
        inc     hl
        ld      a,(K_REC+KR_DRV+NXD_BANK)
        cp      (hl)
        jr      nz,.notroot
        ld      a,(K_REC+KR_DRV+NXD_DEV)
        cp      (ix+V_DEV)
        jr      nz,.notroot
        ld      a,(K_REC+KR_DRV+NXD_LUN)
        cp      (ix+V_LUN)
        jr      nz,.notroot
        ld      hl,K_REC+KR_FIRST
        push    ix
        pop     de
        push    hl
        ld      hl,V_FIRST
        add     hl,de
        ex      de,hl
        pop     hl
        ld      b,4
.first: ld      a,(de)
        cp      (hl)
        jr      nz,.notroot
        inc     hl
        inc     de
        djnz    .first
        pop     af
        push    af
        ld      (K_BLK_ROOT),a
.notroot:
        ; The line.
        ld      hl,s_mnt
        k_call  API_CON_PUTS
        pop     af
        push    af
        add     a,'a'
        k_call  API_CON_PUTC
        ld      hl,s_two
        k_call  API_CON_PUTS
        ld      a,(SG+SV_NAMELEN)
        ld      b,a
        ld      hl,SG+SV_NAME
.name:  ld      a,b
        or      a
        jr      z,.named
        ld      a,(hl)
        k_call  API_CON_PUTC
        inc     hl
        dec     b
        jr      .name
.named: ld      hl,s_two
        k_call  API_CON_PUTS
        call    bi_devlun_bare
        ld      a,' '
        k_call  API_CON_PUTC
        call    bi_plabel_bare
        ld      hl,s_two
        k_call  API_CON_PUTS
        ld      a,(SG+SV_CTYPE)
        k_call  API_CON_HEX8
        ld      hl,s_two
        k_call  API_CON_PUTS
        ld      hl,(SG+SV_CCOUNT)       ; KB = count / 2
        ld      de,(SG+SV_CCOUNT+2)
        srl     d
        rr      e
        rr      h
        rr      l
        call    bi_dec32
        ld      hl,s_kb
        k_call  API_CON_PUTS
        pop     af
        ld      hl,K_BLK_ROOT
        cp      (hl)
        jr      nz,.nl
        ld      hl,s_root
        k_call  API_CON_PUTS
.nl:    k_call  API_CON_NEWLINE
        ret

; bi_read — DE:HL = a device sector of the current LUN into SG_SCRATCH.
; CF on error. Corrupts everything.
bi_read:
        ld      a,(SG+SV_DEV)
        ld      b,a
        ld      a,(SG+SV_LUN)
        ld      c,a
        ld      a,(SG+SV_DRV)
        k_call  API_BLK_DEV_RW
        ret

; bi_bpb — is SG_SCRATCH a FAT12/16 boot sector? From the FAT
; specification: 512 bytes per sector; sectors per cluster a power of two;
; reserved sectors, root entries, sectors per FAT and total sectors all
; non-zero; 1 to 7 FATs; sectors per FAT below 256 (a FAT32 volume has 0
; root entries and 0 here). Z if so. Corrupts AF, BC, DE, HL.
bi_bpb:
        ld      hl,(SG_SCRATCH+0Bh)
        ld      de,512
        or      a
        sbc     hl,de
        ret     nz
        ld      a,(SG_SCRATCH+0Dh)
        or      a
        jr      z,.no
        ld      b,a
        dec     a
        and     b
        ret     nz                      ; not a power of two
        ld      hl,(SG_SCRATCH+0Eh)
        ld      a,h
        or      l
        jr      z,.no
        ld      a,(SG_SCRATCH+10h)
        dec     a
        cp      7
        jr      nc,.no
        ld      hl,(SG_SCRATCH+11h)
        ld      a,h
        or      l
        jr      z,.no
        ld      hl,(SG_SCRATCH+16h)
        ld      a,h
        or      l
        jr      z,.no                   ; sectors per FAT: 0 is FAT32. A
                                        ; nearly full FAT16 needs 256 of
                                        ; them, so the whole 16 bits count.
        ld      hl,(SG_SCRATCH+13h)
        ld      a,h
        or      l
        jr      nz,.ok                  ; a 16-bit total
        ld      hl,(SG_SCRATCH+20h)
        ld      de,(SG_SCRATCH+22h)
        ld      a,h
        or      l
        or      d
        or      e
        jr      z,.no
.ok:    xor     a                       ; Z
        ret
.no:    or      1                       ; NZ
        ret

; bi_devlun — "  d.l" of the current device and LUN; bi_devlun_bare the
; same without the indent. Corrupts AF, HL.
bi_devlun:
        ld      hl,s_two
        k_call  API_CON_PUTS
bi_devlun_bare:
        ld      a,(SG+SV_DEV)
        add     a,'0'
        k_call  API_CON_PUTC
        ld      a,'.'
        k_call  API_CON_PUTC
        ld      a,(SG+SV_LUN)
        add     a,'0'
        k_call  API_CON_PUTC
        ret

; bi_plabel — " pN", " eN" or " --" for the candidate; bi_plabel_bare
; without the leading space. Corrupts AF.
bi_plabel:
        ld      a,' '
        k_call  API_CON_PUTC
bi_plabel_bare:
        ld      a,(SG+SV_PKIND)
        or      a
        jr      nz,.notpri
        ld      a,'p'
        k_call  API_CON_PUTC
        ld      a,(SG+SV_PRI)
        add     a,'0'
        k_call  API_CON_PUTC
        ret
.notpri:
        dec     a
        jr      nz,.super
        ld      a,'e'
        k_call  API_CON_PUTC
        ld      a,(SG+SV_NLOG)
        add     a,'0'
        k_call  API_CON_PUTC
        ret
.super: ld      a,'-'
        k_call  API_CON_PUTC
        ld      a,'-'
        k_call  API_CON_PUTC
        ret

; bi_dec32 — DE:HL in decimal, no leading zeros. Divides by ten until
; nothing is left, pushing the digits, then prints them. Corrupts
; everything.
bi_dec32:
        ld      b,0                     ; digits pushed
.div:   ; DE:HL / 10 -> DE:HL, remainder in C
        push    bc
        ld      c,0
        ld      b,32
.bit:   add     hl,hl
        rl      e
        rl      d
        rl      c
        ld      a,c
        sub     10
        jr      c,.next
        ld      c,a
        inc     l
.next:  djnz    .bit
        ld      a,c
        pop     bc
        push    af                      ; the digit
        inc     b
        ld      a,h
        or      l
        or      d
        or      e
        jr      nz,.div
.print: pop     af
        add     a,'0'
        k_call  API_CON_PUTC
        djnz    .print
        ret

s_nodriver:   db "no storage driver",10,0
s_novolumes:  db ": no volumes",10,0
s_noautomap:  db ": not for automatic mounting, skipped",10,0
s_unreadable: db ": unreadable, skipped",10,0
s_badchain:   db " chain: bad link, chain ends",10,0
s_morelogical: db ": more logical partitions, not walked",10,0
s_badboot:    db ": bad boot sector, skipped",10,0
s_morevolumes: db "more volumes, not mounted",10,0
s_mnt:        db "/mnt/",0
s_two:        db "  ",0
s_kb:         db " KB",0
s_root:       db " /",0

; ---------------------------------------------------------------------
; The cache: BUF_N headers at SG_HDR, buffers at SG_BUF; write-through,
; so a header is (volume, sector, age) and nothing is ever dirty; the
; least recently touched buffer is the victim. The two most recent
; buffers returned are valid: the newest is the most recently touched and
; the next miss evicts the least.

; ks_cache_init — every header free, the clock at 0.
ks_cache_init:
        ld      hl,SG_HDR
        ld      b,BUF_N
.free:  ld      (hl),VOL_NONE
        ld      de,H_SIZE
        add     hl,de
        djnz    .free
        xor     a
        ld      (SG+SV_CLOCK),a
        ret

; ks_bget — A = volume, DE:HL = sector -> HL = the buffer, in page 1; CF
; with A = the errno when the read failed. Corrupts everything.
ks_bget:
        call    bc_find
        jr      z,.hit
        push    af
        push    hl
        push    de
        call    bc_victim               ; ix -> the header to fill
        pop     de
        pop     hl
        pop     af
        ld      (ix+H_VOL),a
        ld      (ix+H_SEC),l
        ld      (ix+H_SEC+1),h
        ld      (ix+H_SEC+2),e
        ld      (ix+H_SEC+3),d
        push    ix
        call    bc_index                ; c = the buffer's index
        ld      a,c
        add     a,SLOT_BUF0
        ld      c,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        ld      l,(ix+H_SEC)            ; the sector again: bc_index used HL
        ld      h,(ix+H_SEC+1)
        ld      e,(ix+H_SEC+2)
        ld      d,(ix+H_SEC+3)
        ld      a,(ix+H_VOL)
        or      a                       ; CF clear: read
        k_call  API_BLK_RW
        pop     ix
        jr      nc,.hit
        ld      (ix+H_VOL),VOL_NONE     ; not filled after all
        ret                             ; CF, A = errno
.hit:   call    bc_touch
        call    bc_index
        ld      a,c
        add     a,a                     ; c * 512 = (c * 2) << 8
        ld      h,a
        ld      l,0
        ld      de,SG_BUF
        add     hl,de
        or      a
        ret

; ks_bwrite — HL = a buffer returned by ks_bget: written to its sector.
; CF with the errno on failure, and the buffer is dropped. Corrupts
; everything.
ks_bwrite:
        ld      a,h
        sub     high SG_BUF
        srl     a                       ; the buffer's index
        ld      c,a
        add     a,a
        add     a,a
        add     a,a                     ; * 8
        ld      e,a
        ld      d,0
        ld      ix,SG_HDR
        add     ix,de
        ld      a,c
        add     a,SLOT_BUF0
        ld      c,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        ld      l,(ix+H_SEC)
        ld      h,(ix+H_SEC+1)
        ld      e,(ix+H_SEC+2)
        ld      d,(ix+H_SEC+3)
        ld      a,(ix+H_VOL)
        push    ix
        scf                             ; write
        k_call  API_BLK_RW
        pop     ix
        ret     nc
        ld      (ix+H_VOL),VOL_NONE
        ret

; ks_bdrop — A = volume, DE:HL = sector: its buffer, if any, is freed.
ks_bdrop:
        call    bc_find
        ret     nz
        ld      (ix+H_VOL),VOL_NONE
        ret

; ks_binval — A = volume: every buffer of it freed.
ks_binval:
        ld      ix,SG_HDR
        ld      b,BUF_N
        ld      de,H_SIZE
.scan:  cp      (ix+H_VOL)
        jr      nz,.next
        ld      (ix+H_VOL),VOL_NONE
.next:  add     ix,de
        djnz    .scan
        ret

; ks_bread_direct — A = volume, DE:HL = sector, B = segment, C = slot:
; straight from the driver into the target. The cache never holds a copy
; newer than the disk, so nothing else is needed.
ks_bread_direct:
        or      a                       ; read
        jp      K_API+3*API_BLK_RW

; ks_bwrite_direct — the same, writing: the cached copy of the sector, if
; any, is dropped first.
ks_bwrite_direct:
        push    af
        push    bc
        push    de
        push    hl
        call    ks_bdrop
        pop     hl
        pop     de
        pop     bc
        pop     af
        scf                             ; write
        jp      K_API+3*API_BLK_RW

; bc_find — A = volume, DE:HL = sector: Z with IX -> the header when it
; is cached, else NZ. Preserves A, DE, HL; corrupts BC, IX.
bc_find:
        ld      ix,SG_HDR
        ld      b,BUF_N
.scan:  cp      (ix+H_VOL)
        jr      nz,.next
        push    hl
        ld      c,a
        ld      a,(ix+H_SEC)
        cp      l
        jr      nz,.no
        ld      a,(ix+H_SEC+1)
        cp      h
        jr      nz,.no
        ld      a,(ix+H_SEC+2)
        cp      e
        jr      nz,.no
        ld      a,(ix+H_SEC+3)
        cp      d
        jr      nz,.no
        ld      a,c
        pop     hl
        ret                             ; Z from the last cp
.no:    ld      a,c
        pop     hl
.next:  push    de
        ld      de,H_SIZE
        add     ix,de
        pop     de
        djnz    .scan
        inc     b                       ; NZ, A untouched
        ret

; bc_victim — IX -> the first free header, else the one of least age.
; Corrupts AF, BC, DE, HL, IY.
bc_victim:
        ld      ix,SG_HDR
        push    ix
        pop     iy                      ; iy = the best so far
        ld      c,(ix+H_AGE)
        ld      b,BUF_N
        ld      de,H_SIZE
.scan:  ld      a,(ix+H_VOL)
        cp      VOL_NONE
        jr      z,.free
        ld      a,(ix+H_AGE)
        cp      c
        jr      nc,.next
        ld      c,a
        push    ix
        pop     iy
.next:  add     ix,de
        djnz    .scan
        push    iy
        pop     ix
        ret
.free:  ret                             ; ix -> it

; bc_touch — IX -> a header: its age is the clock's next value; when the
; clock wraps every age goes to 0 and the clock to 1. Preserves IX;
; corrupts AF, BC, DE, HL.
bc_touch:
        ld      a,(SG+SV_CLOCK)
        inc     a
        jr      nz,.set
        push    ix
        ld      ix,SG_HDR
        ld      b,BUF_N
        ld      de,H_SIZE
.zero:  ld      (ix+H_AGE),0
        add     ix,de
        djnz    .zero
        pop     ix
        ld      a,1
.set:   ld      (SG+SV_CLOCK),a
        ld      (ix+H_AGE),a
        ret

; bc_index — IX -> a header: C = its index. Corrupts AF, HL.
bc_index:
        push    ix
        pop     hl
        ld      a,l
        sub     low SG_HDR
        rrca
        rrca
        rrca
        and     1Fh
        ld      c,a
        ret

; ---------------------------------------------------------------------
; The RTC

RTC_ADDR        equ 0B4h
RTC_DATA        equ 0B5h

; ks_rtc_read — HL = the date as FAT keeps it ((year - 1980) << 9 |
; month << 5 | day), DE = the time (hour << 11 | minute << 5 | second /
; 2), from the RP5C01's block 0, read until the seconds agree before and
; after; 1980-01-01 00:00 when a register is not BCD -- what a machine
; without an RTC reads -- or when what the digits assemble to is outside
; the range a date and a time have, which is what a clock with no battery
; left reads. Corrupts everything.
ks_rtc_read:
        ld      a,13                    ; the mode register: block 0, timer on
        out     (RTC_ADDR),a
        ld      a,08h
        out     (RTC_DATA),a
        ld      b,3                     ; passes
.pass:  push    bc
        ld      hl,SG+SV_RTC
        ld      c,0
        ld      b,13
.reg:   ld      a,c
        out     (RTC_ADDR),a
        in      a,(RTC_DATA)
        and     0Fh
        ld      (hl),a
        inc     hl
        inc     c
        djnz    .reg
        xor     a
        out     (RTC_ADDR),a
        in      a,(RTC_DATA)
        and     0Fh
        ld      hl,SG+SV_RTC
        cp      (hl)
        pop     bc
        jr      z,.stable
        djnz    .pass
.stable:
        ; Every time register a BCD digit (the weekday is not looked at),
        ; and every assembled value within the range a FAT stamp allows.
        ; A clock whose battery has gone reads digits that are each below
        ; ten and together mean nothing -- 29:12:35, or a date of all
        ; zeroes -- and such a stamp must not reach a directory entry.
        ld      hl,SG+SV_RTC
        ld      b,13
.check: ld      a,(hl)
        cp      10
        jr      nc,.none
        inc     hl
        djnz    .check
        ld      hl,SG+SV_RTC+7          ; day, month, year
        call    .pair
        or      a                       ; day 1-31
        jr      z,.none
        cp      32
        jr      nc,.none
        ld      e,a                     ; day
        call    .pair
        or      a                       ; month 1-12
        jr      z,.none
        cp      13
        jr      nc,.none
        ld      d,a                     ; month
        call    .pair
        ld      c,a                     ; year - 1980: two digits never
                                        ; leave the field's own 0-127
        ld      h,0
        ld      l,d
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; month << 5
        ld      d,0
        add     hl,de                   ; + day
        ld      a,c
        add     a,a
        ld      d,a                     ; year << 9 = (year << 1) << 8
        ld      e,0
        add     hl,de
        push    hl                      ; the date
        ld      hl,SG+SV_RTC+0          ; seconds, minutes, hours
        call    .pair
        cp      60                      ; second 0-59
        jr      nc,.none1
        srl     a
        ld      e,a                     ; second / 2
        call    .pair
        cp      60                      ; minute 0-59
        jr      nc,.none1
        ld      d,a                     ; minute
        call    .pair
        cp      24                      ; hour 0-23
        jr      nc,.none1
        ld      c,a                     ; hour
        ld      h,0
        ld      l,d
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; minute << 5
        ld      d,0
        add     hl,de                   ; + second / 2
        ld      a,c
        add     a,a
        add     a,a
        add     a,a
        ld      d,a                     ; hour << 11 = (hour << 3) << 8
        ld      e,0
        add     hl,de
        ex      de,hl                   ; de = the time
        pop     hl                      ; hl = the date
        ret
.none1: pop     af                      ; drop the date already computed
.none:  ld      hl,0021h                ; 1980-01-01
        ld      de,0
        ret
; .pair — HL -> units, tens: A = the number; HL past them.
.pair:  ld      a,(hl)
        inc     hl
        ld      c,a
        ld      a,(hl)
        inc     hl
        add     a,a
        ld      b,a
        add     a,a
        add     a,a
        add     a,b                     ; tens * 10
        add     a,c
        ret
