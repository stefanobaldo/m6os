; The file allocation table, in the switched part: the next cluster of a
; chain, a cluster's first sector, the cursor an open file keeps — and,
; for the write side, an entry set, a free cluster found and a chain
; freed. FAT12 and FAT16. Every read and every change goes through the
; first copy of the table; the copies are written from the same buffers by
; ks_bflush (ks_blk.asm), so they cannot diverge. Runs under the window
; and the storage gate, like ks_blk.asm, and keeps no variable of its own.
; Every sector here is relative to its volume, so blk_rw's bounds check
; stands between a corrupt chain and the neighbouring partition.

; fat_mnt — A = a volume: IX -> its mount row. Corrupts DE; preserves A.
fat_mnt:
        push    af
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; * 32
        ld      e,a
        ld      d,0
        ld      ix,SG_MNT
        add     ix,de
        pop     af
        ret

; fat_fsec — A = a sector index into the FAT of volume (SG+VV_T+2): HL ->
; its buffer, through bget; CF with the errno from it. The index is kept
; aside while fat_mnt runs: fat_mnt uses DE. Corrupts everything.
fat_fsec:
        ld      (SG+VV_T+5),a
        ld      a,(SG+VV_T+2)
        call    fat_mnt
        ld      l,(ix+M_FAT)
        ld      h,(ix+M_FAT+1)
        ld      a,(SG+VV_T+5)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      e,(ix+M_FAT+2)
        ld      d,(ix+M_FAT+3)
        jr      nc,.nc
        inc     de
.nc:    ld      a,(SG+VV_T+2)
        k_call  API_BGET
        ret

; fat_get — A = a volume, HL = a cluster: HL = its entry in the table as
; stored, 12 or 16 bits, nothing judged; CF with the errno when the sector
; could not be read. A FAT12 entry that straddles two sectors is two bgets:
; the two most recent buffers are both valid, by the cache's contract.
; Corrupts everything.
fat_get:
        ld      (SG+VV_T),hl            ; the cluster, for its parity
        ld      (SG+VV_T+2),a           ; the volume
        call    fat_mnt
        bit     0,(ix+M_FLAGS)
        jr      nz,.f16
        ; FAT12: byte offset o = c + c / 2; the entry is the word at o.
        ld      d,h
        ld      e,l
        srl     d
        rr      e
        add     hl,de                   ; hl = o (below 6128)
        ld      (SG+VV_T+6),hl
        ld      a,h
        rrca                            ; o >> 9
        and     7Fh
        call    fat_fsec                ; hl -> the sector's buffer
        ret     c
        ld      de,(SG+VV_T+6)
        ld      a,d
        and     1
        ld      d,a                     ; de = o & 1FFh
        add     hl,de
        ld      c,(hl)                  ; the low byte
        ld      a,e
        cp      0FFh
        jr      nz,.same
        ld      a,d
        or      a
        jr      z,.same                 ; o & 1FFh = 0FFh: the same sector
        ; The word straddles: its high byte is the next sector's first.
        ld      a,c
        ld      (SG+VV_T+3),a
        ld      hl,(SG+VV_T+6)
        ld      a,h
        rrca
        and     7Fh
        inc     a                       ; (o >> 9) + 1
        call    fat_fsec
        ret     c
        ld      b,(hl)
        ld      a,(SG+VV_T+3)
        ld      c,a
        jr      .word12
.same:  inc     hl
        ld      b,(hl)
.word12:
        ld      h,b
        ld      l,c                     ; hl = the 16-bit word
        ld      a,(SG+VV_T)
        rrca                            ; the cluster's parity
        jr      nc,.even
        srl     h                       ; odd: the high 12 bits
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        or      a
        ret
.even:  ld      a,h
        and     0Fh
        ld      h,a                     ; even: the low 12 bits
        or      a
        ret
        ; FAT16: the word at 2c, in sector c >> 8.
.f16:   ld      a,h
        call    fat_fsec
        ret     c
        ld      a,(SG+VV_T)
        ld      e,a
        ld      d,0
        add     hl,de
        add     hl,de                   ; + (c & FFh) * 2
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl                   ; hl = the word
        or      a
        ret

; fat_next — A = a volume, HL = a cluster: HL = the cluster that follows it
; in its chain, NZ; or Z with CF clear at the chain's end; or CF with A =
; E_IO on a value no chain may hold — 0, 1, the bad-cluster mark, or one
; past the volume's clusters. Corrupts everything.
fat_next:
        call    fat_get
        ret     c
        ld      a,(SG+VV_T+2)
        call    fat_mnt
        ld      a,h
        bit     0,(ix+M_FLAGS)
        jr      nz,.f16
        cp      0Fh                     ; FAT12: FF7h bad, FF8h-FFFh the end
        jr      nz,.value
        jr      .low
.f16:   cp      0FFh                    ; FAT16: FFF7h bad, FFF8h-FFFFh the end
        jr      nz,.value
.low:   ld      a,l
        cp      0F7h
        jr      z,.bad
        cp      0F8h
        jr      nc,.end
        ; A value must name a data cluster: 2 to M_NCLUS + 1.
.value: ld      a,h
        or      a
        jr      nz,.range
        ld      a,l
        cp      2
        jr      c,.bad
.range: ld      e,(ix+M_NCLUS)
        ld      d,(ix+M_NCLUS+1)
        inc     de                      ; the last cluster
        push    hl
        or      a
        sbc     hl,de                   ; value - last
        pop     hl
        jr      z,.ok
        jr      nc,.bad                 ; above the last
.ok:    or      1                       ; NZ, CF clear
        ret
.end:   xor     a                       ; Z, CF clear
        ret
.bad:   ld      a,E_IO
        scf
        ret

; fat_set — A = a volume, HL = a cluster, DE = the value: the entry in the
; first table's buffer changed and the buffer marked dirty, for bflush to
; write to every copy. Nothing reaches the disk here. A FAT12 entry that
; straddles two sectors marks both buffers. CF with the errno. Corrupts
; everything.
fat_set:
        ld      (SG+VV_T),hl
        ld      (SG+VV_T+2),a
        ld      (SG+VW_VAL),de
        call    fat_mnt
        bit     0,(ix+M_FLAGS)
        jp      nz,.f16
        ld      d,h
        ld      e,l
        srl     d
        rr      e
        add     hl,de                   ; hl = o
        ld      (SG+VV_T+6),hl
        ld      a,h
        rrca
        and     7Fh
        call    fat_fsec
        ret     c
        ld      (SG+VW_BUF0),hl
        ld      de,(SG+VV_T+6)
        ld      a,d
        and     1
        ld      d,a
        add     hl,de                   ; hl -> the low byte
        ld      (SG+VW_P0),hl
        ld      c,(hl)
        ld      a,e
        cp      0FFh
        jr      nz,.same
        ld      a,d
        or      a
        jr      z,.same
        ld      a,c
        ld      (SG+VV_T+3),a
        ld      hl,(SG+VV_T+6)
        ld      a,h
        rrca
        and     7Fh
        inc     a
        call    fat_fsec                ; the next sector: the high byte
        ret     c
        ld      (SG+VW_P1),hl
        ld      b,(hl)
        ld      a,(SG+VV_T+3)
        ld      c,a
        jr      .word
.same:  inc     hl
        ld      (SG+VW_P1),hl
        ld      b,(hl)
.word:  ; bc = the word as it is; the new one keeps the other entry's nibble.
        ld      hl,(SG+VW_VAL)
        ld      a,(SG+VV_T)
        rrca
        jr      nc,.even
        add     hl,hl                   ; odd: value << 4, low nibble kept
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,c
        and     0Fh
        or      l
        ld      l,a
        jr      .store
.even:  ld      a,b                     ; even: value, high nibble kept
        and     0F0h
        or      h
        ld      h,a
.store: ld      a,l
        ld      de,(SG+VW_P0)
        ld      (de),a
        ld      a,h
        ld      de,(SG+VW_P1)
        ld      (de),a
        ld      hl,(SG+VW_BUF0)
        call    bc_mark_fat
        ld      hl,(SG+VW_P1)
        ld      a,h
        and     0FEh                    ; the buffer holding the high byte
        ld      h,a
        ld      l,0
        call    bc_mark_fat             ; the same buffer, or the next sector's
        or      a
        ret
.f16:   ld      a,h
        call    fat_fsec
        ret     c
        push    hl
        ld      a,(SG+VV_T)
        ld      e,a
        ld      d,0
        add     hl,de
        add     hl,de
        ld      de,(SG+VW_VAL)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     hl
        call    bc_mark_fat
        or      a
        ret

; fat_alloc — A = a volume, HL = the cluster to start after: HL = a free
; cluster, now marked as a chain's end in the table's buffer; CF with
; E_NOSPC when a whole circuit of the table finds none, or the errno.
; Next-fit: the probe starts at HL + 1, wraps from the last cluster to 2,
; and stops at the first entry that reads 0 — so a file extended from its
; tail is laid out contiguously and the probe hits the FAT sector already
; in the cache, and a full volume costs one pass over the table before
; ENOSPC, never earlier. On FAT16 the pass scans each sector's words in
; place; on FAT12 it reads entry by entry. Corrupts everything.
fat_alloc:
        ld      (SG+VW_AVOL),a
        call    fat_mnt
        ld      e,(ix+M_NCLUS)
        ld      d,(ix+M_NCLUS+1)
        ld      (SG+VW_ALEFT),de        ; probes left: every cluster once
        inc     de
        ld      (SG+VW_ALAST),de        ; the last cluster
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.start                ; below the last: start after it
        ld      hl,1                    ; else the circuit begins at 2
.start: ld      (SG+VW_ACUR),hl
        bit     0,(ix+M_FLAGS)
        jr      nz,.f16
        ; FAT12: entry by entry.
.probe: call    .advance
        jr      c,.nospc
        ld      hl,(SG+VW_ACUR)
        ld      a,(SG+VW_AVOL)
        call    fat_get
        ret     c
        ld      a,h
        or      l
        jr      nz,.probe
        jr      .found
        ; FAT16: the sector holding the next cluster's entry, then its words
        ; from that entry to the sector's end.
.f16:   call    .advance
        jr      c,.nospc
.fetch: ld      hl,(SG+VW_ACUR)
        ld      a,(SG+VW_AVOL)
        ld      (SG+VV_T+2),a
        ld      a,h
        call    fat_fsec                ; hl -> the sector's buffer
        ret     c
        ld      a,(SG+VW_ACUR)
        ld      e,a
        ld      d,0
        add     hl,de
        add     hl,de                   ; hl -> the entry
.word:  ld      a,(hl)
        inc     hl
        or      (hl)
        inc     hl
        jr      z,.found
        call    .advance
        jr      c,.nospc
        ld      a,(SG+VW_ACUR)
        or      a
        jr      z,.fetch                ; a new sector
        cp      2
        jr      nz,.word
        ld      a,(SG+VW_ACUR+1)
        or      a
        jr      z,.fetch                ; wrapped to 2
        jr      .word
.found: ld      a,(SG+VW_AVOL)
        call    fat_mnt
        ld      de,0FFFh
        bit     0,(ix+M_FLAGS)
        jr      z,.eoc
        ld      de,0FFFFh
.eoc:   ld      hl,(SG+VW_ACUR)
        ld      a,(SG+VW_AVOL)
        call    fat_set
        ret     c
        ld      hl,(SG+VW_ACUR)
        or      a
        ret
.nospc: ld      a,E_NOSPC
        scf
        ret
; .advance — VW_ACUR one on, 2 after the last cluster; CF when every
; cluster has had its probe. Preserves HL; corrupts AF, DE.
.advance:
        push    hl
        ld      hl,(SG+VW_ALEFT)
        ld      a,h
        or      l
        jr      z,.out
        dec     hl
        ld      (SG+VW_ALEFT),hl
        ld      hl,(SG+VW_ACUR)
        inc     hl
        ld      de,(SG+VW_ALAST)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.in
        jr      z,.in
        ld      hl,2
.in:    ld      (SG+VW_ACUR),hl
        pop     hl
        or      a
        ret
.out:   pop     hl
        scf
        ret

; fat_free_chain — A = a volume, HL = a chain's first cluster: every entry
; of the chain set to 0, in the buffers, for bflush. A bad link stops the
; walk with E_IO; what was freed before it stays freed. Called only once
; no directory entry points at the chain. Corrupts everything.
fat_free_chain:
        ld      (SG+VW_AVOL),a
.link:  ld      (SG+VW_ACUR),hl
        ld      a,(SG+VW_AVOL)
        call    fat_next
        ret     c
        push    af                      ; Z: this was the last
        push    hl                      ; the next
        ld      hl,(SG+VW_ACUR)
        ld      de,0
        ld      a,(SG+VW_AVOL)
        call    fat_set
        pop     hl
        jr      c,.err
        pop     af
        ret     z
        jr      .link
.err:   pop     de
        scf
        ret

; fat_sector — A = a volume, HL = a cluster: DE:HL = its first sector,
; M_DATA + (c - 2) << M_SPCSH; CF with A = E_IO when c is not a data
; cluster. Corrupts everything.
fat_sector:
        call    fat_mnt
        ld      a,h
        or      a
        jr      nz,.range
        ld      a,l
        cp      2
        jr      c,.bad
.range: ld      e,(ix+M_NCLUS)
        ld      d,(ix+M_NCLUS+1)
        inc     de
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.ok
        jr      nc,.bad
.ok:    dec     hl
        dec     hl                      ; c - 2
        ld      de,0
        ld      a,(ix+M_SPCSH)
        or      a
        jr      z,.add
        ld      b,a
.shift: add     hl,hl
        rl      e
        rl      d
        djnz    .shift
.add:   ld      c,(ix+M_DATA)
        ld      b,(ix+M_DATA+1)
        add     hl,bc
        ex      de,hl
        ld      c,(ix+M_DATA+2)
        ld      b,(ix+M_DATA+3)
        adc     hl,bc
        ex      de,hl                   ; de = high, hl = low
        or      a
        ret
.bad:   ld      a,E_IO
        scf
        ret

; fat_walk — A = a volume, HL = a cluster, BC = steps: HL = the cluster BC
; links further along the chain; Z with CF clear if the chain ends first;
; CF with the errno on a bad link. Corrupts everything.
fat_walk:
        ld      (SG+VV_T+4),a
.step:  ld      a,b
        or      c
        jr      z,.done
        push    bc
        ld      a,(SG+VV_T+4)
        call    fat_next
        pop     bc
        ret     c
        ret     z                       ; ended early
        dec     bc
        jr      .step
.done:  or      1                       ; NZ
        ret

; of_cursor — IX -> an open-file row whose OF_CLUS is OF_CLUS_NONE: set it
; to the cluster holding OF_POS, walking from OF_FIRST; A = the shift that
; turns a position into a cluster index (9 + M_SPCSH for a file, 4 +
; M_SPCSH for a directory). Out: CF with the errno; Z with CF clear when
; the chain ends before the position (OF_CLUS = OF_CLUS_END); NZ with
; OF_CLUS set. Preserves IX; corrupts the rest.
of_cursor:
        ld      b,a
        ld      l,(ix+OF_POS)
        ld      h,(ix+OF_POS+1)
        ld      e,(ix+OF_POS+2)
        ld      d,(ix+OF_POS+3)
.shift: srl     d
        rr      e
        rr      h
        rr      l
        djnz    .shift
        ld      b,h
        ld      c,l                     ; bc = the cluster index
        ld      l,(ix+OF_FIRST)
        ld      h,(ix+OF_FIRST+1)
        ld      a,(ix+OF_VOL)
        push    ix
        call    fat_walk
        pop     ix
        ret     c
        jr      z,.end
        ld      (ix+OF_CLUS),l
        ld      (ix+OF_CLUS+1),h
        ret                             ; NZ
.end:   ld      (ix+OF_CLUS),low OF_CLUS_END
        ld      (ix+OF_CLUS+1),high OF_CLUS_END
        ret                             ; Z, CF clear
