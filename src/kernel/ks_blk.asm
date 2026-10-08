; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The block layer's cold half, in the switched part: the enumeration of
; drivers, devices, LUNs and partitions into the volume table, the boot
; listing, the buffer cache and the RTC read. Runs under the window (this
; image in page 2) and the storage gate (the storage segment in page 1),
; and calls the resident through the jump table only. Keeps no variable
; of its own — the image may be a ROM bank — and writes only to the
; storage segment, at SG+offset, where ST_VARS holds what it has to
; remember.; ---------------------------------------------------------------------
; The cache: BUF_N headers at SG_HDR, buffers at SG_BUF; write-through
; at the syscall's grain: a data sector is written the moment it changes,
; a FAT sector is marked dirty (H_FLAGS) by the write side and written to
; every copy by ks_bflush before the syscall returns, so nothing is dirty
; between syscalls. The least recently touched buffer that is not dirty
; is the victim. The two most recent buffers returned are valid: the
; newest is the most recently touched and the next miss evicts the least.
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
        ld      (ix+H_FLAGS),0
        push    ix
        call    bc_index                ; c = the buffer's index
        ld      a,c
        add     a,a
        add     a,SLOT_BUF0             ; its first slot
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

; ks_bwrite — HL = a buffer returned by ks_bget or ks_bzero: written to
; its sector, its dirty bit cleared. CF with the errno on failure, and
; the buffer is dropped. Not for a FAT sector, which bflush writes to
; every copy. Corrupts everything.
ks_bwrite:
        call    bc_header               ; ix -> the header, c = the index
        ld      (ix+H_FLAGS),0
        ld      a,c
        add     a,a
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
        ld      (ix+H_FLAGS),0
        ret

; ks_binval — A = volume: every buffer of it freed.
ks_binval:
        ld      ix,SG_HDR
        ld      b,BUF_N
        ld      de,H_SIZE
.scan:  cp      (ix+H_VOL)
        jr      nz,.next
        ld      (ix+H_VOL),VOL_NONE
        ld      (ix+H_FLAGS),0
.next:  add     ix,de
        djnz    .scan
        ret

; ks_bzero — A = volume, DE:HL = sector: HL = a buffer of zeros standing
; for it, nothing read from the disk — for a sector whose contents are
; about to be replaced whole: a hole, a fresh partial sector, a new
; directory's cluster. The buffer is valid until written or evicted like
; any other; nothing is written here. Corrupts everything.
ks_bzero:
        call    bc_find
        jr      z,.have
        push    af
        push    hl
        push    de
        call    bc_victim
        pop     de
        pop     hl
        pop     af
        ld      (ix+H_VOL),a
        ld      (ix+H_SEC),l
        ld      (ix+H_SEC+1),h
        ld      (ix+H_SEC+2),e
        ld      (ix+H_SEC+3),d
        ld      (ix+H_FLAGS),0
.have:  call    bc_touch
        call    bc_index
        ld      a,c
        add     a,a
        ld      h,a
        ld      l,0
        ld      de,SG_BUF
        add     hl,de
        push    hl
        ld      d,h
        ld      e,l
        inc     de
        ld      (hl),0
        ld      bc,511
        ldir
        pop     hl
        or      a
        ret

; ks_bflush — every dirty buffer written to its sector, a FAT sector (HF_FAT)
; to every copy of the table, each one's bits cleared. A buffer whose write
; fails is freed — the copy in memory is no longer the disk's — and the
; flush goes on; CF with the first errno met. What makes write-through
; true at the syscall's grain: every syscall that dirties a buffer calls
; this before it returns. Corrupts everything.
ks_bflush:
        xor     a
        ld      (SG+SV_FERR),a
        ld      ix,SG_HDR
        ld      b,BUF_N
.scan:  ld      a,(ix+H_VOL)
        cp      VOL_NONE
        jr      z,.next
        bit     0,(ix+H_FLAGS)          ; HF_DIRTY
        jr      z,.next
        push    bc
        call    bf_one
        pop     bc
.next:  ld      de,H_SIZE
        add     ix,de
        djnz    .scan
        ld      a,(SG+SV_FERR)
        or      a
        ret     z
        scf
        ret

; bf_one — IX -> a dirty header: written, to every copy when it is a FAT
; sector. Preserves IX (through SV_FHDR); corrupts the rest.
bf_one:
        ld      (SG+SV_FHDR),ix
        ld      c,1                     ; copies
        bit     1,(ix+H_FLAGS)          ; HF_FAT
        jr      z,.copies
        ld      a,(ix+H_VOL)
        call    fat_mnt                 ; ix -> the mount row
        ld      c,(ix+M_NFATS)
        ld      l,(ix+M_FATSZ)
        ld      h,(ix+M_FATSZ+1)
        ld      (SG+SV_FSTEP),hl
        ld      ix,(SG+SV_FHDR)
.copies:
        ld      a,c
        ld      (SG+SV_FN),a
        ld      l,(ix+H_SEC)
        ld      h,(ix+H_SEC+1)
        ld      (SG+SV_FSEC),hl
        ld      l,(ix+H_SEC+2)
        ld      h,(ix+H_SEC+3)
        ld      (SG+SV_FSEC+2),hl
.copy:  ld      ix,(SG+SV_FHDR)
        call    bc_index
        ld      a,c
        add     a,a
        add     a,SLOT_BUF0
        ld      c,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        ld      hl,(SG+SV_FSEC)
        ld      de,(SG+SV_FSEC+2)
        ld      a,(ix+H_VOL)
        scf                             ; write
        k_call  API_BLK_RW
        jr      c,.fail
        ld      a,(SG+SV_FN)
        dec     a
        ld      (SG+SV_FN),a
        jr      z,.ok
        ld      hl,(SG+SV_FSEC)
        ld      de,(SG+SV_FSTEP)
        add     hl,de
        ld      (SG+SV_FSEC),hl
        jr      nc,.copy
        ld      hl,(SG+SV_FSEC+2)
        inc     hl
        ld      (SG+SV_FSEC+2),hl
        jr      .copy
.ok:    ld      ix,(SG+SV_FHDR)
        ld      (ix+H_FLAGS),0
        ret
.fail:  ld      c,a
        ld      a,(SG+SV_FERR)
        or      a
        jr      nz,.free
        ld      a,c
        ld      (SG+SV_FERR),a
.free:  ld      ix,(SG+SV_FHDR)
        ld      (ix+H_VOL),VOL_NONE
        ld      (ix+H_FLAGS),0
        ret

; bc_header — HL = a buffer's address: IX -> its header, C = its index.
; Corrupts AF, DE.
bc_header:
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
        ret

; bc_mark_fat — HL = a FAT sector's buffer: dirty, and a FAT sector, for
; bflush. Corrupts AF, BC, DE, IX.
bc_mark_fat:
        call    bc_header
        set     0,(ix+H_FLAGS)          ; HF_DIRTY
        set     1,(ix+H_FLAGS)          ; HF_FAT
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

; bc_find — A = volume, DE:HL = sector: Z with IX -> the header that holds
; it, else NZ. Preserves A, DE, HL; corrupts BC, IX. The sector's low byte
; is compared first, one 7-cycle cp (hl) per header, and the rest of the
; key only where it matches; the header pointer steps in L alone, the
; headers lying in one page. Measured in openMSX before this form: ~1 ms
; per call, and four calls per sector written.
bc_find:
        push    af
        push    de
        push    hl
        ld      c,a                     ; c = the volume
        ld      (SG+SV_FKEY),de         ; the sector's high word
        ld      d,h                     ; d = the sector's second byte
        ld      e,l                     ; e = its first
        ; The last hit first: a FAT sector is asked for three times per
        ; cluster, a directory sector sixteen times per listing.
        ld      hl,(SG+SV_LAST)
        ld      a,(hl)
        cp      c
        jr      nz,.all
        inc     hl
        ld      a,(hl)
        cp      e
        jr      nz,.all
        inc     hl
        ld      a,(hl)
        cp      d
        jr      nz,.all
        inc     hl
        ld      a,(SG+SV_FKEY)
        cp      (hl)
        jr      nz,.all
        inc     hl
        ld      a,(SG+SV_FKEY+1)
        cp      (hl)
        jr      nz,.all
        ld      hl,(SG+SV_LAST)
        push    hl
        pop     ix
        pop     hl
        pop     de
        pop     af
        cp      a                       ; Z
        ret
.all:   ld      a,e
        ld      hl,SG_HDR+H_SEC
        ld      b,BUF_N
.scan:  cp      (hl)
        jr      z,.maybe
.next:  ld      a,l
        add     a,H_SIZE
        ld      l,a
        ld      a,e
        djnz    .scan
        pop     hl
        pop     de
        pop     af
        inc     b                       ; NZ
        ret
.maybe: push    hl
        dec     hl
        ld      a,(hl)
        cp      c                       ; the volume; VOL_NONE never equal
        jr      nz,.no
        inc     hl
        inc     hl
        ld      a,(hl)
        cp      d
        jr      nz,.no
        inc     hl
        ld      a,(hl)
        ld      hl,SG+SV_FKEY
        cp      (hl)
        jr      nz,.no
        pop     hl
        push    hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        ld      hl,SG+SV_FKEY+1
        cp      (hl)
        jr      nz,.no
        pop     hl
        ld      a,l
        and     0F8h                    ; the header's first byte
        ld      l,a
        ld      (SG+SV_LAST),hl
        push    hl
        pop     ix
        pop     hl
        pop     de
        pop     af
        cp      a                       ; Z, A untouched
        ret
.no:    pop     hl
        jr      .next

; bc_victim — IX -> the first free header, else the one of least age among
; those neither dirty nor lent: a dirty buffer holds a FAT update the
; syscall has not flushed yet, and at most three are dirty at a time; a
; lent one (HF_LENT, its volume VOL_LENT, which bc_find never matches) is
; the MSX-DOS layer's while a program runs, and dosenter leaves BUF_MIN
; that are not — so a victim is always found. Corrupts AF, BC, DE, HL, IY.
bc_victim:
        ld      ix,SG_HDR
        push    ix
        pop     iy                      ; iy = the best so far
        ld      c,0FFh                  ; older than any age
        ld      b,BUF_N
        ld      de,H_SIZE
.scan:  ld      a,(ix+H_VOL)
        cp      VOL_NONE
        jr      z,.free
        ld      a,(ix+H_FLAGS)          ; dirty, or lent to an MSX-DOS
        and     HF_DIRTY|HF_LENT        ; program: never the victim
        jr      nz,.next
        ld      a,(ix+H_AGE)
        cp      c
        jr      z,.take
        jr      nc,.next
.take:  ld      c,a
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
