; Strings.
;
;   str_cmp     HL and DE -> 0-terminated strings: Z when equal; CF when
;               DE's sorts first. Corrupts AF, DE, HL.
;   str_len     HL -> a string: BC = its length. Corrupts AF.
;   str_copy    HL -> a string, DE -> where to: copied with its 0, DE left
;               on the 0 so the next copy appends. Corrupts AF.
;   str_atoi    HL -> decimal digits: HL = their value, DE -> the first
;               byte that is not a digit; CF when there was no digit.
;               Corrupts AF, BC.
        define STR_INC

str_cmp:
.loop:  ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      .loop

str_len:
        push    hl
        ld      bc,0
.loop:  ld      a,(hl)
        or      a
        jr      z,.done
        inc     hl
        inc     bc
        jr      .loop
.done:  pop     hl
        ret

str_copy:
        push    hl
.loop:  ld      a,(hl)
        ld      (de),a
        or      a
        jr      z,.done
        inc     hl
        inc     de
        jr      .loop
.done:  pop     hl
        ret

str_atoi:
        ex      de,hl
        ld      hl,0
        ld      c,0                     ; c = digits seen
.next:  ld      a,(de)
        sub     '0'
        jr      c,.end
        cp      10
        jr      nc,.end
        inc     c
        push    bc
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl
        add     hl,bc
        add     hl,hl                   ; * 10
        ld      c,a
        ld      b,0
        add     hl,bc                   ; + the digit
        pop     bc
        inc     de
        jr      .next
.end:   ld      a,c
        or      a
        ret     nz
        scf
        ret
