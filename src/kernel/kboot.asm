; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The boot image: what the kernel runs once, at boot, and never again —
; the scheduler's first row, the enumeration of the storage and its
; listing, the cache's first state, the summary of the memory and the
; boot time. Every loader carries it beside the resident and the switched
; image; k_main copies it to KB_BASE, in the loader's page 0, and calls
; its first byte under the storage gate — the storage segment in page 1,
; at SG — with the window closed: nothing here addresses page 2. It calls
; the resident through K_API and K_API2 and nothing else, and writes the
; header's fields and the storage segment only; it is gone once
; sched_release_boot has given the loader's pages away. The rule it
; exists for: the switched image carries only code that runs after the
; boot; what runs once runs from the loader's memory.
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"

        org     KB_BASE

; kb_main — the boot, in the order k_main used to run it through the
; window: process 0's row, the volumes, the cache, process 0's directory,
; the memory lines, the boot time. Corrupts everything.
kb_main:
        call    sched_init
        call    blk_init
        call    cache_init
        ld      a,(K_BLK_ROOT)          ; process 0 starts in /
        ld      (K_PROC+P_CWD),a
        call    mem_summary
        ; boot: N ticks — JIFFY as the loader found it plus the kernel's
        ; own ticks: the whole boot since power-on, in 60 Hz ticks, read
        ; off the screen. Sixteen bits wrap after ~18 minutes of power-on,
        ; which no boot reaches.
        ld      hl,s_boot
        k_call  API_CON_PUTS
        ld      hl,(K_REC+KR_JIFFY)
        ld      de,(K_TICKS)
        add     hl,de
        k_call  API_CON_DEC16
        ld      hl,s_ticks
        k_call  API_CON_PUTS
        k_call  API_CON_NEWLINE
        ret

s_boot:     db  "boot: ",0
s_ticks:    db  " ticks",0

; sched_init — row 0 and the scalars, before anything runs. Corrupts
; everything.
sched_init:
        ld      hl,K_PROC
        ld      (hl),PS_FREE
        ld      de,K_PROC+1
        ld      bc,NPROC*P_SIZE-1
        ldir
        ld      hl,K_PROC
        ld      (hl),PS_RUN             ; process 0: runnable, pid 0, a
        ld      (K_CUR),hl              ; ring of one
        ld      a,low K_PROC
        ld      (K_PROC+P_NEXT),a
        ld      hl,0
        ld      (K_PID),hl
        ld      a,1
        ld      (K_NRUN),a
        ld      a,PP_NONE
        ld      (K_PROC+P_PPID),a
        ld      hl,K_MAP                ; its pages: what is mapped now,
        ld      de,K_PROC+P_SEG         ; until sched_release_boot
        ld      bc,3
        ldir
        ; Every descriptor closed, then process 0's three: the keyboard on
        ; 0, the console on 1 and 2.
        ld      hl,K_FD
        ld      (hl),FD_NONE
        ld      de,K_FD+1
        ld      bc,NPROC*NOFILE-1
        ldir
        ld      a,FD_KBD
        ld      (K_FD+0),a
        ld      a,FD_CON
        ld      (K_FD+1),a
        ld      (K_FD+2),a
        ; The extension table: zero, every row waiting on no pipe.
        ld      hl,K_PX
        ld      b,NPROC
.px:    ld      (hl),0FFh               ; PX_WCHAN
        inc     hl
        xor     a
        ld      c,PX_SIZE-1
.pxz:   ld      (hl),a
        inc     hl
        dec     c
        jr      nz,.pxz
        djnz    .px
        ret

; ---------------------------------------------------------------------
; The enumeration

; blk_init — every driver in the record, every device and LUN it has,
; every partition of each: the volume table, the boot volume and the
; listing. Corrupts everything.
blk_init:
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
        call    bi_isext
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

; bi_isext — A = a partition entry's type: Z when it opens an extended
; chain. 05h is the CHS form; 0Fh is the same thing addressed by LBA,
; which is what a partitioner writes for a container beginning past the
; CHS limit — a card of a few gigabytes reaches that, and the FDISK this
; ecosystem ships writes 0Fh there. Preserves IX.
bi_isext:
        cp      PT_EXTENDED
        ret     z
        cp      PT_EXTENDED_LBA
        ret

; bi_chain — IX -> an extended entry of the MBR: walk its EBRs. Each EBR's
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
        call    bi_isext
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
        push    ix
        call    bi_mount                ; the mount row from the BPB
        pop     ix
        pop     af
        push    af
        inc     a
        ld      (K_BLK_NVOL),a
        ld      hl,SG+SV_FOUND
        inc     (hl)
        ld      hl,SG+SV_NDEV
        inc     (hl)
        ; The boot volume: the record's driver, device, LUN and first
        ; sector — or, when the record names no driver (a loader with no
        ; drive under it, the kernel ROM), the first volume found.
        ld      a,(K_REC+KR_DRV+NXD_SLOT)
        or      a
        jr      nz,.recdrv
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        jr      nz,.notroot             ; the first is the root already
        jr      .root
.recdrv: ld     a,(SG+SV_DRV)
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
.root:  pop     af
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

; bi_mount — A = the row's index; the candidate's boot sector is in
; SG_SCRATCH, validated: fill mount row A from it. Every sector relative to
; the volume: the FAT at the reserved count, the root after the FATs, the
; data after the root; the type from the cluster count, never from the
; string at 36h (the CI image's is garbage). Corrupts everything, the
; boot sector's volume id included.
bi_mount:
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; * 32
        ld      e,a
        ld      d,0
        ld      ix,SG_MNT
        add     ix,de
        ld      a,(SG_SCRATCH+15h)      ; the media descriptor
        ld      (ix+M_MEDIA),a
        ld      a,(SG_SCRATCH+26h)      ; the volume id at 27h, when the
        cp      29h                     ;   sector has one: the extended
        jr      z,.volid                ;   signature, or MSX-DOS 2's
        ld      a,(SG_SCRATCH+20h)      ;   "VOL_ID" at 20h; else -1
        cp      'V'
        jr      z,.volid
        ld      hl,-1
        ld      (SG_SCRATCH+27h),hl
        ld      (SG_SCRATCH+29h),hl
.volid: push    ix
        pop     hl
        ld      de,M_VOLID
        add     hl,de
        ex      de,hl
        ld      hl,SG_SCRATCH+27h
        ld      bc,4
        ldir
        ld      a,(SG_SCRATCH+0Dh)      ; sectors per cluster
        ld      (ix+M_SPC),a
        ld      b,0
.log2:  rrca
        jr      c,.shifted
        inc     b
        jr      .log2
.shifted:
        ld      (ix+M_SPCSH),b
        ld      a,(SG_SCRATCH+10h)      ; FATs
        ld      (ix+M_NFATS),a
        ld      hl,(SG_SCRATCH+16h)     ; sectors per FAT
        ld      (ix+M_FATSZ),l
        ld      (ix+M_FATSZ+1),h
        ld      hl,(SG_SCRATCH+0Eh)     ; reserved: the first FAT
        ld      (ix+M_FAT),l
        ld      (ix+M_FAT+1),h
        ld      (ix+M_FAT+2),0
        ld      (ix+M_FAT+3),0
        ld      de,(SG_SCRATCH+16h)
        ld      a,(SG_SCRATCH+10h)
        ld      bc,0                    ; bc = the high word of the sum
.fats:  add     hl,de
        jr      nc,.nc
        inc     bc
.nc:    dec     a
        jr      nz,.fats
        ld      (ix+M_ROOT),l           ; root = reserved + fats * fatsz
        ld      (ix+M_ROOT+1),h
        ld      (ix+M_ROOT+2),c
        ld      (ix+M_ROOT+3),b
        push    hl
        push    bc
        ld      hl,(SG_SCRATCH+11h)     ; root entries * 32 / 512 = / 16
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (ix+M_ROOTN),l
        ld      (ix+M_ROOTN+1),h
        ex      de,hl
        pop     bc
        pop     hl
        add     hl,de                   ; data = root + rootn
        jr      nc,.nc2
        inc     bc
.nc2:   ld      (ix+M_DATA),l
        ld      (ix+M_DATA+1),h
        ld      (ix+M_DATA+2),c
        ld      (ix+M_DATA+3),b
        ; clusters = (total - data) >> spcsh, total the 16-bit field or
        ; the 32-bit one.
        push    hl
        push    bc
        ld      hl,(SG_SCRATCH+13h)
        ld      de,0
        ld      a,h
        or      l
        jr      nz,.total
        ld      hl,(SG_SCRATCH+20h)
        ld      de,(SG_SCRATCH+22h)
.total: pop     bc                      ; bc = data.hi
        ex      (sp),hl                 ; hl = data.lo, stack = total.lo
        ex      de,hl                   ; hl = total.hi, de = data.lo
        ex      (sp),hl                 ; hl = total.lo, stack = total.hi
        or      a
        sbc     hl,de                   ; total.lo - data.lo
        ex      de,hl                   ; de = difference.lo
        pop     hl                      ; total.hi
        sbc     hl,bc                   ; hl = difference.hi
        ex      de,hl                   ; hl = lo, de = hi
        ld      a,(ix+M_SPCSH)
        or      a
        jr      z,.clusters
        ld      b,a
.shift: srl     d
        rr      e
        rr      h
        rr      l
        djnz    .shift
.clusters:
        ld      (ix+M_NCLUS),l
        ld      (ix+M_NCLUS+1),h
        ld      (ix+M_HINT),2           ; a new file's first cluster is
        ld      (ix+M_HINT+1),0         ; looked for from the start
        ld      de,4085
        or      a
        sbc     hl,de
        ld      a,0                     ; FAT12
        jr      c,.type
        ld      a,MF_FAT16
.type:  ld      (ix+M_FLAGS),a
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

; cache_init — every header free, the clock at 0; and every row of the
; open-file table (ks_vfs.asm) nobody's, since this is where the storage
; segment's tables are given their first state.
cache_init:
        ld      hl,SG_HDR
        ld      b,BUF_N
.free:  ld      (hl),VOL_NONE
        push    hl
        ld      de,H_FLAGS
        add     hl,de
        ld      (hl),0
        pop     hl
        ld      de,H_SIZE
        add     hl,de
        djnz    .free
        xor     a
        ld      (SG+SV_CLOCK),a
        ld      hl,SG_HDR
        ld      (SG+SV_LAST),hl         ; a free header: no false hit
        ld      hl,SG+ST_OFT
        ld      b,OFT_N
.rows:  ld      (hl),VOL_NONE           ; OF_VOL
        ld      de,OFT_SIZE
        add     hl,de
        djnz    .rows
        xor     a                       ; no creation, no chain in progress
        ld      (SG+VW_CREATE),a        ; (ks_vfs.asm, ks_lfn.asm)
        ld      (SG+VW_EXCL),a
        ld      (SG+VW_GATHER),a
        ld      (SG+VL_N),a
        ld      (SG+VR_LN),a
        ret

; mem_summary — the boot summary of the memory: one line per mapper found,
; the primary's free count, the cap when one is in force, and how many
; mappers were found beyond the table.
mem_summary:
        k_call  API_MEM_INFO
        ld      b,(hl)                  ; mappers
        inc     hl
.map:   ld      a,b
        or      a
        jp      z,.over
        push    bc
        push    hl
        ld      hl,s_mapper
        k_call  API_CON_PUTS
        pop     hl
        ld      a,(hl)                  ; MM_SLOT
        push    hl
        ld      c,a
        and     3
        add     a,'0'
        k_call  API_CON_PUTC
        bit     7,c
        jr      z,.segs
        ld      a,'.'
        k_call  API_CON_PUTC
        ld      a,c
        rrca
        rrca
        and     3
        add     a,'0'
        k_call  API_CON_PUTC
.segs:  ld      hl,s_colon
        k_call  API_CON_PUTS
        pop     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; MM_SEGS
        inc     hl
        push    hl
        ex      de,hl
        k_call  API_CON_DEC16
        ld      hl,s_segments
        k_call  API_CON_PUTS
        pop     hl
        bit     0,(hl)                  ; MMF_PRIMARY
        inc     hl
        push    hl
        jr      z,.notused
        ld      hl,s_primary
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        ld      h,b
        ld      l,c                     ; free
        k_call  API_CON_DEC16
        ld      hl,s_free
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_MEMCAP)
        or      a
        jr      z,.line
        ld      hl,s_usable
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        push    de
        ex      de,hl                   ; usable
        k_call  API_CON_DEC16
        ld      hl,s_usable2
        k_call  API_CON_PUTS
        pop     hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; usable * 16 = K
        k_call  API_CON_DEC16
        ld      hl,s_usable3
        k_call  API_CON_PUTS
        jr      .line
.notused:
        ld      hl,s_notused
        k_call  API_CON_PUTS
.line:  k_call  API_CON_NEWLINE
        pop     hl
        pop     bc
        dec     b
        jp      .map
.over:  k_call  API_MEM_INFO
        or      a
        ret     z
        push    af
        ld      hl,s_more
        k_call  API_CON_PUTS
        pop     af
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        ld      hl,s_more2
        k_call  API_CON_PUTS
        ret

s_mapper:   db  "mapper ",0
s_colon:    db  ": ",0
s_segments: db  " segments, ",0
s_primary:  db  "primary, ",0
s_free:     db  " free",0
s_usable:   db  " (",0
s_usable2:  db  " usable, mem=",0
s_usable3:  db  ")",0
s_notused:  db  "not used",0
s_more:     db  "and ",0
s_more2:    db  " more, not scanned",10,0

kb_end:
        ASSERT  kb_end <= KB_BASE+KB_MAX
