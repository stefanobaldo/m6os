; Helpers shared by the programs under tests/ for the half that runs after
; the takeover, calling the resident through its jump table. Include from
; inside the block a program assembles for K_END.

; k_cmp512 — compare 512 bytes at HL and DE. Z if equal; otherwise NZ with
; HL = offset of the first difference, B = byte at HL, C = byte at DE.
k_cmp512:
        push    hl
        ld      bc,512
.loop:  ld      a,(de)
        cp      (hl)
        jr      nz,.diff
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        pop     hl
        ret
.diff:  ld      b,(hl)
        ld      c,a
        pop     de
        or      a
        sbc     hl,de                   ; the offset — 0 when the first byte
        ld      a,b                     ; differs, so Z cannot come from it:
        cp      c                       ; the two bytes differ, hence NZ
        ret

; k_fill_c — KT_BUF_C byte i = (i and 0FFh) xor A.
k_fill_c:
        ld      c,a
        ld      hl,KT_BUF_C
        ld      d,2
.outer: ld      b,0
        ld      e,0
.inner: ld      a,e
        xor     c
        ld      (hl),a
        inc     hl
        inc     e
        djnz    .inner
        dec     d
        jr      nz,.outer
        ret

; k_muldiv — HL = HL * DE / BC, through a 24-bit product; HL and the
; quotient must fit 16 bits. Multiplies by repeated addition and divides by
; repeated subtraction: slow and obviously right, for numbers printed once.
; Corrupts AF, BC, DE.
k_muldiv:
        push    bc
        ld      b,h
        ld      c,l                     ; bc = multiplier
        ld      hl,0
        exx
        ld      hl,0                    ; hl' = quotient; c' = product high
        ld      c,0
        exx
.mul:   ld      a,b
        or      c
        jr      z,.divide
        add     hl,de
        jr      nc,.nc
        exx
        inc     c
        exx
.nc:    dec     bc
        jr      .mul
.divide:
        pop     de                      ; de = divisor
.div:   exx
        ld      a,c
        exx
        or      a
        jr      nz,.sub                 ; high byte set: certainly >= divisor
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.done
.sub:   or      a
        sbc     hl,de
        jr      nc,.nb
        exx
        dec     c
        exx
.nb:    exx
        inc     hl
        exx
        jr      .div
.done:  exx
        push    hl
        exx
        pop     hl
        ret

; k_hundredths — HL = a value in hundredths, printed as N.NN.
; Corrupts AF, BC, DE, HL.
k_hundredths:
        ld      de,100
        ld      bc,0
.div:   or      a
        sbc     hl,de
        jr      c,.rem
        inc     bc
        jr      .div
.rem:   add     hl,de                   ; hl = remainder, bc = quotient
        push    hl
        ld      h,b
        ld      l,c
        k_call  API_CON_DEC16
        ld      a,'.'
        k_call  API_CON_PUTC
        pop     hl
        ld      a,l
        ld      b,'0'-1
.tens:  inc     b
        sub     10
        jr      nc,.tens
        add     a,10
        ld      c,a
        ld      a,b
        k_call  API_CON_PUTC
        ld      a,c
        add     a,'0'
        k_call  API_CON_PUTC
        ret

; k_dec8 — A in decimal. Corrupts AF, DE, HL.
k_dec8:
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        ret

; k_call_hl — call the routine at HL.
k_call_hl:
        jp      (hl)
