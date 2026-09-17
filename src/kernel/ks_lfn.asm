; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Long names, in the switched part. A long name is a chain of entries
; with attribute 0Fh laid before a short entry, the last piece of the
; name first: each carries an ordinal (bits 0-4, 1-20; 40h on the first
; on disk), thirteen UCS-2 characters at offsets 1, 14 and 28, and at
; 0Dh the checksum of the short entry's eleven-byte name. The name ends
; at a 0000h character, or with its last piece full, and is padded with
; FFFFh. A directory scan feeds every such entry to lfn_feed, which
; reads the chain into ST_LNAME, and asks lfn_close at every live short
; entry whether the chain behind it is that entry's: open, complete, and
; carrying its checksum. The state of the chain being read is VL_*; what
; the scan hands on beside VR_ENT is VR_LN, VR_LSEC and VR_LIDX.
;
; Only ASCII is read: a character outside 20h-7Eh becomes ?, and a name
; holding one opens by its short alias alone, since ? is no part of a
; path.

; lfn_reset — A = the mode: 0 every chain is read (readdir, getcwd), 1
; only a chain of VL_WANT characters is, the rest dying on their first
; entry (a lookup). No chain open, no result. Corrupts AF.
lfn_reset:
        ld      (SG+VL_MODE),a
        xor     a
        ld      (SG+VL_N),a
        ld      (SG+VR_LN),a
        ret

; lfn_feed — HL -> an entry with attribute 0Fh, in a 512-aligned sector
; buffer, VR_DSEC = its sector: the chain state advanced by it — opened
; when its sequence byte has 40h, continued when its ordinal and checksum
; follow the chain's, else dead until the next short entry. Its thirteen
; characters go to ST_LNAME at 13 x (ordinal - 1). Preserves HL;
; corrupts the rest.
lfn_feed:
        push    hl
        ld      a,(hl)
        bit     6,a
        jr      nz,.first
        ; A continuation: the chain open and alive, the ordinal the one
        ; expected, the checksum the chain's.
        and     1Fh
        ld      b,a
        ld      a,(SG+VL_N)
        or      a
        jp      z,.out                  ; no chain: an orphaned part
        ld      a,(SG+VL_DEAD)
        or      a
        jp      nz,.out
        ld      a,(SG+VL_NEXT)
        dec     a
        jp      z,.dead                 ; a part below 1
        cp      b
        jp      nz,.dead
        ld      (SG+VL_NEXT),a
        ld      de,13
        add     hl,de
        ld      a,(hl)
        ld      hl,SG+VL_SUM
        cp      (hl)
        jp      nz,.dead
        pop     hl
        push    hl
        call    .copy
        jp      c,.dead                 ; a terminator in a middle part
        jp      .out
.first: and     1Fh
        jp      z,.dead                 ; ordinal 0
        cp      21
        jr      nc,.dead                ; past NAME_MAX
        ld      (SG+VL_N),a
        ld      (SG+VL_NEXT),a
        xor     a
        ld      (SG+VL_DEAD),a
        ld      de,13
        add     hl,de
        ld      a,(hl)
        ld      (SG+VL_SUM),a
        pop     hl
        push    hl
        ; Where the chain starts, for whoever removes it: the sector, and
        ; the index from the entry's place in its buffer.
        ld      de,(SG+VR_DSEC)
        ld      (SG+VL_LSEC),de
        ld      de,(SG+VR_DSEC+2)
        ld      (SG+VL_LSEC+2),de
        ld      a,l
        rlca
        rlca
        rlca
        and     7
        ld      c,a
        ld      a,h
        and     1
        add     a,a
        add     a,a
        add     a,a
        or      c
        ld      (SG+VL_LIDX),a
        ; In a lookup, the length filter: as many entries as the
        ; component needs, and this last piece as long as its remainder.
        ld      a,(SG+VL_MODE)
        or      a
        jr      z,.copyfirst
        ld      a,(SG+VL_WANT)
        ld      c,0
.div:   cp      14
        jr      c,.rem
        sub     13
        inc     c
        jr      .div
.rem:   inc     c                       ; c = entries wanted, a = the rest
        ld      (SG+VL_LEN),a
        ld      a,(SG+VL_N)
        cp      c
        jr      nz,.dead
.copyfirst:
        ld      a,(SG+VL_N)
        ld      b,a
        call    .copy                   ; a = characters in this piece
        ld      c,a
        ld      a,(SG+VL_MODE)
        or      a
        jr      z,.len
        ld      a,(SG+VL_LEN)
        cp      c
        jr      nz,.dead
.len:   ld      a,(SG+VL_N)             ; the name's length: 13 (n - 1) + c
        dec     a
        ld      b,a
        ld      a,0
        jr      z,.add                  ; one part
.m13:   add     a,13
        djnz    .m13
.add:   add     a,c
        jr      c,.dead                 ; past 255
        or      a
        jr      z,.dead                 ; an empty name
        ld      (SG+VL_LEN),a
.out:   pop     hl
        ret
.dead:  ld      a,1
        ld      (SG+VL_DEAD),a
        pop     hl
        ret
; .copy — HL -> the entry, B = its ordinal: its thirteen characters to
; ST_LNAME + 13 (B - 1); A = how many came before a terminator, CF when
; one was met (and written). Corrupts everything.
.copy:  ld      a,b
        dec     a
        ld      c,a
        add     a,a
        add     a,a
        add     a,c
        add     a,a
        add     a,c
        add     a,c
        add     a,c                     ; 13 (b - 1), at most 247
        ld      e,a
        ld      d,0
        push    hl
        ld      hl,SG+ST_LNAME
        add     hl,de
        ex      de,hl                   ; de -> where the piece goes
        pop     hl
        inc     hl                      ; the first character, at 1
        ld      c,0
        ld      b,5
        call    .part
        ret     c
        inc     hl                      ; past 11, 12, 13
        inc     hl
        inc     hl
        ld      b,6
        call    .part
        ret     c
        inc     hl                      ; past 26, 27
        inc     hl
        ld      b,2
        call    .part
        ld      a,c
        ret
; .part — B characters from HL to DE, C counting them: CF at a 0000h,
; written as the terminator. A character with a high byte, or a low byte
; outside 20h-7Eh, is written as ?.
.part:  ld      a,(hl)                  ; the low byte
        inc     hl
        or      a
        jr      nz,.ch
        ld      a,(hl)                  ; the high byte
        or      a
        jr      nz,.q
        xor     a
        ld      (de),a                  ; 0000h: the end
        ld      a,c
        scf
        ret
.ch:    ld      a,(hl)
        or      a
        jr      nz,.q
        dec     hl
        ld      a,(hl)
        inc     hl
        cp      20h
        jr      c,.q
        cp      7Fh
        jr      c,.store
.q:     ld      a,'?'
.store: ld      (de),a
        inc     de
        inc     hl
        inc     c
        djnz    .part
        ld      a,c
        or      a                       ; CF clear
        ret

; lfn_close — HL -> a live short entry: A = the entries of the valid
; chain behind it, 0 (Z) when it has none — a chain is valid when it is
; open, alive, complete (the next ordinal expected is 1) and carries the
; checksum of these eleven bytes. Then ST_LNAME is terminated and VR_LN,
; VR_LSEC and VR_LIDX describe the chain. The chain state is cleared
; either way. Preserves HL; corrupts the rest.
lfn_close:
        push    hl
        ld      a,(SG+VL_N)
        or      a
        jr      z,.none
        ld      a,(SG+VL_DEAD)
        or      a
        jr      nz,.none
        ld      a,(SG+VL_NEXT)
        dec     a
        jr      nz,.none
        call    lfn_sum
        ld      hl,SG+VL_SUM
        cp      (hl)
        jr      nz,.none
        ld      a,(SG+VL_LEN)
        ld      e,a
        ld      d,0
        ld      hl,SG+ST_LNAME
        add     hl,de
        ld      (hl),0
        ld      hl,SG+VL_LSEC
        ld      de,SG+VR_LSEC
        ld      bc,5
        ldir
        ld      a,(SG+VL_N)
        ld      (SG+VR_LN),a
        xor     a
        ld      (SG+VL_N),a
        ld      a,(SG+VR_LN)
        or      a
        pop     hl
        ret
.none:  xor     a
        ld      (SG+VL_N),a
        ld      (SG+VR_LN),a
        pop     hl
        ret

; lfn_sum — HL -> an eleven-byte short name: A = its checksum, the sum
; rotated right before each byte is added. Corrupts B, HL.
lfn_sum:
        xor     a
        ld      b,11
.b:     rrca
        add     a,(hl)
        inc     hl
        djnz    .b
        ret

; lfn_valid — DE -> a component, C = its length: CF when it cannot be a
; long name — empty, a byte outside 20h-7Eh or one of " * / : < > ? \ |,
; a dot or a space last, or dots alone. Preserves DE, C; corrupts AF, B,
; HL.
lfn_valid:
        ld      a,c
        or      a
        jr      z,.bad
        push    de
        ld      b,c
        ld      h,1                     ; 1 while every byte was a dot
.ch:    ld      a,(de)
        cp      '.'
        jr      z,.next
        ld      h,0
        cp      20h
        jr      c,.badpop
        cp      7Fh
        jr      nc,.badpop
        push    hl
        push    bc
        ld      hl,.forbid
        ld      bc,.nforbid
        cpir
        pop     bc
        pop     hl
        jr      z,.badpop
.next:  inc     de
        djnz    .ch
        dec     de
        ld      a,(de)                  ; the last byte
        pop     de
        cp      '.'
        jr      z,.bad
        cp      ' '
        jr      z,.bad
        ld      a,h
        or      a
        jr      nz,.bad                 ; dots alone
        ret                             ; CF clear
.badpop:
        pop     de
.bad:   scf
        ret
.forbid: db     '"*/:<>?\|'
.nforbid equ    $-.forbid

; lfn_ascii — DE -> a component, C = its length: CF when a byte of it is
; outside 20h-7Eh, which no name made here may hold. Preserves DE, C;
; corrupts AF, B, HL.
lfn_ascii:
        ld      b,c
        ld      h,d
        ld      l,e
.b:     ld      a,(hl)
        cp      20h
        jr      c,.bad
        cp      7Fh
        jr      nc,.bad
        inc     hl
        djnz    .b
        or      a
        ret
.bad:   scf
        ret

; lfn_cmp — the component at (VV_P), VL_WANT bytes, against the name in
; ST_LNAME, letters without regard to case: Z when they are the same
; name. Corrupts everything.
lfn_cmp:
        ld      hl,(SG+VV_P)
        ld      de,SG+ST_LNAME
        ld      a,(SG+VL_WANT)
        ld      b,a
.c:     ld      a,(de)
        call    upper
        ld      c,a
        ld      a,(hl)
        call    upper
        cp      c
        ret     nz
        inc     hl
        inc     de
        djnz    .c
        ld      a,(de)
        or      a                       ; Z: the name ends here too
        ret

; ---------------------------------------------------------------------
; Making a name

; lfn_prepare — the last component of a lookup that will create it, at
; (VV_P) for VL_WANT bytes, VL_SHORT and VV_MIXED from name83: what the
; new name needs — VW_NLFN parts (0 when the short entry alone carries
; it: a name that fits 8.3 with each part in one case), VW_RNEED slots,
; and with parts its alias in VW_ALIAS, digit still to choose — and the
; scan's gathering armed: VW_GATHER, the run and the alias map empty.
; Corrupts everything.
lfn_prepare:
        xor     a
        ld      (SG+VW_RCNT),a
        ld      (SG+VW_RFOUND),a
        ld      (SG+VW_AMAP),a
        ld      (SG+VW_AMAP+1),a
        ld      (SG+VW_NLFN),a
        inc     a
        ld      (SG+VW_GATHER),a
        ld      a,(SG+VL_SHORT)
        or      a
        jr      z,.chain
        ld      a,(SG+VV_MIXED)
        or      a
        jr      z,.short
.chain: ld      a,(SG+VL_WANT)          ; the parts: (length + 12) / 13
        ld      b,0
.div:   inc     b
        sub     13
        jr      z,.parts
        jr      nc,.div
.parts: ld      a,b
        ld      (SG+VW_NLFN),a
        call    lfn_alias
.short: ld      a,(SG+VW_NLFN)
        inc     a
        ld      (SG+VW_RNEED),a
        ret

; lfn_alias — the component at (VV_P), VL_WANT bytes: VW_ALIAS = its
; alias with the digit still to choose: the base's first six characters
; that a short name allows, in upper case, spaces and dots dropped, any
; other it refuses as _; then ~ and a space for the digit; then the
; extension's first three, treated the same, after the last dot when
; one follows the base. VW_ATPOS = where the ~ is. Leading dots are not
; the base's, so .profile makes PROFIL~1. Corrupts everything.
lfn_alias:
        ld      hl,SG+VW_ALIAS
        ld      b,11
.pad:   ld      (hl),' '
        inc     hl
        djnz    .pad
        ld      hl,(SG+VV_P)
        ld      a,(SG+VL_WANT)
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      (SG+VW_AEND),hl         ; past the component
        ld      hl,(SG+VV_P)
.lead:  ld      a,(hl)
        cp      '.'
        jr      nz,.start
        inc     hl
        jr      .lead                   ; dots alone were refused before
.start: ld      (SG+VW_ABASE),hl
        ld      de,0                    ; -> the last dot, 0 none
.dots:  ld      a,(hl)
        cp      '.'
        jr      nz,.nd
        ld      d,h
        ld      e,l
.nd:    inc     hl
        push    hl
        ld      bc,(SG+VW_AEND)
        or      a
        sbc     hl,bc
        pop     hl
        jr      nz,.dots
        ld      (SG+VW_AEXT),de
        ; The base, up to the last dot or the end.
        ld      hl,(SG+VW_ABASE)
        ld      de,SG+VW_ALIAS
        xor     a
        ld      (SG+VW_ATPOS),a         ; characters taken so far
.bch:   push    hl
        ld      bc,(SG+VW_AEND)
        or      a
        sbc     hl,bc
        pop     hl
        jr      z,.tilde                ; the end
        push    hl
        ld      bc,(SG+VW_AEXT)
        or      a
        sbc     hl,bc
        pop     hl
        jr      z,.tilde                ; the last dot: the base ends
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.bch
        cp      '.'
        jr      z,.bch
        call    .short
        ld      (de),a
        inc     de
        ld      a,(SG+VW_ATPOS)
        inc     a
        ld      (SG+VW_ATPOS),a
        cp      6
        jr      c,.bch
.tilde: ld      a,'~'
        ld      (de),a
        ; The extension, after the last dot when it is past the base's
        ; start.
        ld      hl,(SG+VW_AEXT)
        ld      a,h
        or      l
        ret     z
        ld      bc,(SG+VW_ABASE)
        or      a
        sbc     hl,bc
        ret     c                       ; the last dot led: no extension
        ld      hl,(SG+VW_AEXT)
        inc     hl
        ld      de,SG+VW_ALIAS+8
        ld      b,3
.ech:   push    hl
        ld      bc,(SG+VW_AEND)
        or      a
        sbc     hl,bc
        pop     hl
        ret     z
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.ech
        cp      '.'
        jr      z,.ech
        call    .short
        ld      (de),a
        inc     de
        djnz    .ech
        ret
; .short — A = a character of a long name: upper case, or _ when a short
; name refuses it. Corrupts F.
.short: call    upper
        cp      21h
        jr      c,.under
        push    hl
        push    bc
        ld      hl,.refused
        ld      bc,.nrefused
        cpir
        pop     bc
        pop     hl
        ret     nz
.under: ld      a,'_'
        ret
.refused:       db  '"*+,/:;<=>?[\]|'
.nrefused       equ $-.refused

; lfn_hash — the component at (VV_P), VL_WANT bytes: VW_ALIAS given the
; NT form for a name whose nine numbered aliases are taken — two
; characters of the base, four hexadecimal digits of a hash of the name,
; ~1. VW_ATPOS = 6. Corrupts everything.
lfn_hash:
        ld      hl,(SG+VV_P)
        ld      a,(SG+VL_WANT)
        ld      b,a
        ld      de,0
.h:     ld      a,(hl)
        inc     hl
        ex      de,hl
        add     hl,hl                   ; the hash rotated left, the byte
        jr      nc,.nc                  ; added
        inc     l
.nc:    ld      c,a
        ld      a,l
        add     a,c
        ld      l,a
        ld      a,h
        adc     a,0
        ld      h,a
        ex      de,hl
        djnz    .h
        ld      hl,SG+VW_ALIAS+2
        ld      a,d
        call    .hex
        ld      a,e
        call    .hex
        ld      (hl),'~'
        inc     hl
        ld      (hl),'1'
        ld      a,6
        ld      (SG+VW_ATPOS),a
        ret
.hex:   push    af
        rrca
        rrca
        rrca
        rrca
        call    .digit
        pop     af
.digit: and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,.put
        add     a,'A'-'0'-10
.put:   ld      (hl),a
        inc     hl
        ret

; lfn_track — a scan gathering for a creation (VW_GATHER): HL -> an
; entry, C = its index, VR_DSEC = its sector, A = what it is — 0 a free
; slot, 1 a live short entry, 2 a long-name part. The run of free slots
; is counted and its start kept until it reaches VW_RNEED; a short entry
; with the alias's base and extension and a digit 1-9 after ~ sets that
; digit's bit in VW_AMAP. Preserves HL, BC; corrupts AF, DE.
lfn_track:
        push    hl
        push    bc
        or      a
        jr      nz,.live
        ld      a,(SG+VW_RFOUND)
        or      a
        jp      nz,.out
        ld      a,(SG+VW_RCNT)
        or      a
        jr      nz,.more
        ld      hl,(SG+VR_DSEC)         ; the run starts here
        ld      (SG+VW_RSEC),hl
        ld      hl,(SG+VR_DSEC+2)
        ld      (SG+VW_RSEC+2),hl
        ld      a,c
        ld      (SG+VW_RIDX),a
        xor     a
.more:  inc     a
        ld      (SG+VW_RCNT),a
        ld      hl,SG+VW_RNEED
        cp      (hl)
        jp      c,.out
        ld      a,1
        ld      (SG+VW_RFOUND),a
        jp      .out
.live:  ld      b,a
        ld      (SG+VW_AEND),hl         ; the entry, for its extension
        ld      a,(SG+VW_RFOUND)
        or      a
        jr      nz,.map
        xor     a
        ld      (SG+VW_RCNT),a          ; the run is broken
.map:   dec     b
        jp      nz,.out                 ; a part: no alias
        ld      a,(SG+VW_NLFN)
        or      a
        jp      z,.out                  ; a short name: no alias to number
        ; The base, the ~, the digit, a space after it, the extension.
        ld      a,(SG+VW_ATPOS)
        ld      b,a
        ld      de,SG+VW_ALIAS
        or      a
        jr      z,.at
.base:  ld      a,(de)
        cp      (hl)
        jp      nz,.out
        inc     hl
        inc     de
        djnz    .base
.at:    ld      a,(hl)
        cp      '~'
        jp      nz,.out
        inc     hl
        ld      a,(hl)
        sub     '1'
        cp      9
        jp      nc,.out
        inc     a
        ld      b,a                     ; the digit, 1-9
        ld      a,(SG+VW_ATPOS)
        cp      6
        jr      z,.ext
        inc     hl
        ld      a,(hl)
        cp      ' '
        jp      nz,.out
.ext:   ld      hl,(SG+VW_AEND)         ; the entry again, for its extension
        ld      de,8
        add     hl,de
        ld      de,SG+VW_ALIAS+8
        ld      a,(de)
        cp      (hl)
        jp      nz,.out
        inc     hl
        inc     de
        ld      a,(de)
        cp      (hl)
        jp      nz,.out
        inc     hl
        inc     de
        ld      a,(de)
        cp      (hl)
        jp      nz,.out
        ld      hl,SG+VW_AMAP           ; bit b of the map
        ld      a,b
        cp      8
        jr      c,.low
        inc     hl
        sub     8
.low:   inc     a
        ld      c,1
.bit:   dec     a
        jr      z,.set
        sla     c
        jr      .bit
.set:   ld      a,(hl)
        or      c
        ld      (hl),a
.out:   pop     bc
        pop     hl
        ret

; lfn_track_end — the scan met the directory's end at a slot (A = 0: the
; FE_END entry at index C of VR_DSEC, VV_SN sectors left after it) or ran
; out of sectors (A = 1): the run reaching the end is the one, when the
; slots to the end hold VW_RNEED — always in a subdirectory, which
; grows; counted in the root, which cannot. Corrupts everything.
lfn_track_end:
        ld      b,a
        ld      a,(SG+VW_RFOUND)
        or      a
        ret     nz
        ld      a,b
        or      a
        jr      nz,.nosector
        ld      a,(SG+VW_RCNT)
        or      a
        jr      nz,.counted
        ld      hl,(SG+VR_DSEC)         ; the run starts at FE_END
        ld      (SG+VW_RSEC),hl
        ld      hl,(SG+VR_DSEC+2)
        ld      (SG+VW_RSEC+2),hl
        ld      a,c
        ld      (SG+VW_RIDX),a
.counted:
        ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        jr      nz,.found               ; a subdirectory grows
        ; The root: the free slots to its end are this sector's from C on
        ; and sixteen per sector left, plus the run counted before.
        ld      a,16
        sub     c
        ld      e,a
        ld      hl,(SG+VV_SN)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      d,0
        add     hl,de
        ld      a,(SG+VW_RCNT)
        ld      e,a
        add     hl,de
        ld      a,(SG+VW_RNEED)
        ld      e,a
        or      a
        sbc     hl,de
        ret     c                       ; not enough: no run
.found: ld      a,1
        ld      (SG+VW_RFOUND),a
        ret
.nosector:
        ld      a,(SG+VW_RCNT)          ; free slots at the end, if any:
        or      a                       ; a subdirectory continues them in
        ret     z                       ; the cluster it grows by
        ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        jr      nz,.found
        ret

; lfn_digit — VW_ALIAS with its digit: the lowest of 1-9 whose bit is
; clear in VW_AMAP; with all nine taken, the hash form, which a second
; scan confirms absent — VR_ENT is kept across it in VW_PENT. CF with
; E_NOSPC when that one exists too, or the errno. Corrupts everything.
lfn_digit:
        ld      hl,(SG+VW_AMAP)
        srl     h
        rr      l                       ; bit 1 first
        ld      b,9
        ld      c,'1'
.bit:   srl     h
        rr      l                       ; the digit's bit into the carry
        jr      nc,.free
        inc     c
        djnz    .bit
        ; All nine taken: the hash form, looked for as a short name.
        call    lfn_hash
        ld      hl,SG+VR_ENT
        ld      de,SG+VW_PENT
        ld      bc,FE_SIZEOF
        ldir
        ld      hl,SG+VW_ALIAS
        ld      de,SG+VV_NAME
        ld      bc,11
        ldir
        ld      a,1
        ld      (SG+VL_SHORT),a
        xor     a
        ld      (SG+VW_GATHER),a
        ld      hl,SG+VL_WANT           ; the name's length, kept: no chain
        ld      a,(hl)                  ; has no characters, so none matches
        ld      (SG+VW_PPOS),a
        ld      (hl),0
        inc     a
        call    lfn_reset
        call    dir_find
        push    af
        ld      hl,SG+VW_PENT
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        ld      a,(SG+VW_PPOS)
        ld      (SG+VL_WANT),a
        pop     af
        jr      nc,.taken
        cp      E_NOENT
        scf
        ret     nz
        or      a
        ret
.taken: ld      a,E_NOSPC
        scf
        ret
.free:  ld      a,(SG+VW_ATPOS)
        inc     a
        ld      e,a
        ld      d,0
        ld      hl,SG+VW_ALIAS
        add     hl,de
        ld      (hl),c
        or      a
        ret

; lfn_part — A = a part's ordinal, 1 to VW_NLFN: VW_PENT = that part of
; the new name — the ordinal, 40h on the last, its thirteen characters
; from the component at (VV_P), the terminator after the last and FFFFh
; beyond, attribute 0Fh, the checksum VL_SUM, cluster 0. Corrupts
; everything.
lfn_part:
        ld      hl,SG+VW_PENT
        ld      de,SG+VW_PENT+1
        ld      bc,FE_SIZEOF-1
        ld      (hl),0
        ldir
        ld      hl,SG+VW_NLFN
        cp      (hl)
        jr      nz,.notlast
        or      40h
.notlast:
        ld      (SG+VW_PENT),a
        and     1Fh
        dec     a
        ld      c,a
        add     a,a
        add     a,a
        add     a,c
        add     a,a
        add     a,c
        add     a,c
        add     a,c                     ; 13 (ordinal - 1): the first character
        ld      (SG+VW_PPOS),a
        ld      a,FE_LFN
        ld      (SG+VW_PENT+FE_ATTR),a
        ld      a,(SG+VL_SUM)
        ld      (SG+VW_PENT+13),a
        ld      de,SG+VW_PENT+1
        ld      b,5
        call    .chars
        ld      de,SG+VW_PENT+14
        ld      b,6
        call    .chars
        ld      de,SG+VW_PENT+28
        ld      b,2
; .chars — B characters from the component at VW_PPOS on, to DE: a byte
; and 0 each; the terminator 0000h at the length; FFFFh past it.
.chars: ld      a,(SG+VW_PPOS)
        ld      hl,SG+VL_WANT
        cp      (hl)
        jr      c,.ch
        jr      z,.term
        ld      a,0FFh
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
        jr      .n
.term:  xor     a
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
        jr      .n
.ch:    ld      hl,(SG+VV_P)
        ld      c,a
        push    bc
        ld      b,0
        add     hl,bc
        pop     bc
        ld      a,(hl)
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        inc     de
.n:     ld      a,(SG+VW_PPOS)
        inc     a
        ld      (SG+VW_PPOS),a
        djnz    .chars
        ret
