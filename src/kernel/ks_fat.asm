; The file allocation table, in the switched part: the next cluster of a
; chain, a cluster's first sector, and the cursor an open file keeps —
; FAT12 and FAT16, read only, the first copy of the table alone. Runs
; under the window and the storage gate, like ks_blk.asm, and keeps no
; variable of its own. Every sector here is relative to its volume, so
; blk_rw's bounds check stands between a corrupt chain and the
; neighbouring partition.

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

; fat_next — A = a volume, HL = a cluster: HL = the cluster that follows it
; in its chain, NZ; or Z with CF clear at the chain's end; or CF with A =
; E_IO on a value no chain may hold — 0, 1, the bad-cluster mark, or one
; past the volume's clusters. A FAT12 entry that straddles two sectors is
; two bgets: the two most recent buffers are both valid, by the cache's
; contract. Corrupts everything.
fat_next:
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
        call    .fatsec                 ; hl -> the sector's buffer
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
        call    .fatsec
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
        jr      .got12
.even:  ld      a,h
        and     0Fh
        ld      h,a                     ; even: the low 12 bits
.got12: ld      a,h
        cp      0Fh
        jr      nz,.value
        ld      a,l
        cp      0F7h
        jr      z,.bad                  ; FF7h: a bad cluster
        cp      0F8h
        jr      nc,.end                 ; FF8h-FFFh: the end
        jr      .value
        ; FAT16: the word at 2c, in sector c >> 8.
.f16:   ld      a,h
        call    .fatsec
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
        ld      a,h
        cp      0FFh
        jr      nz,.value
        ld      a,l
        cp      0F7h
        jr      z,.bad
        cp      0F8h
        jr      nc,.end
        ; A value must name a data cluster: 2 to M_NCLUS + 1.
.value: ld      a,(SG+VV_T+2)
        call    fat_mnt
        ld      a,h
        or      a
        jr      nz,.low
        ld      a,l
        cp      2
        jr      c,.bad
.low:   ld      e,(ix+M_NCLUS)
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
; .fatsec — A = a sector index into the FAT of volume (SG+VV_T+2): HL ->
; its buffer, through bget; CF with the errno from it. The index is kept
; aside while fat_mnt runs: fat_mnt uses DE.
.fatsec:
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
