; Bytes and lines out of lib/in.inc's buffer. Include after it.
;
;   in_getc     A = the next byte, CF clear; CF set at the end or on an
;               error, with in_err = the errno or 0. Preserves BC, DE, HL.
;   in_line     DE -> a buffer, BC = its size: the next line without its
;               LF, 0-terminated, BC = its length; a line that does not
;               fit is cut to what fits, the rest dropped, and in_cut set.
;               CF set at the end of the input with nothing read.
;               Corrupts everything.
        define LINE_INC

in_getc:
        push    hl
        push    de
        ld      hl,(in_ptr)
        ld      de,(in_end)
        or      a
        sbc     hl,de
        jr      nz,.have
        push    bc
        call    in_fill
        jr      c,.errp
        ld      a,b
        or      c
        pop     bc
        jr      z,.eof
.have:  ld      hl,(in_ptr)
        ld      a,(hl)
        inc     hl
        ld      (in_ptr),hl
        pop     de
        pop     hl
        or      a
        ret
.errp:  pop     bc
        jr      .err
.eof:   xor     a
.err:   ld      (in_err),a
        pop     de
        pop     hl
        scf
        ret

in_line:
        xor     a
        ld      (in_cut),a
        push    de                      ; the start
        dec     bc
        push    bc                      ; the room, the 0 excluded
        ld      hl,0                    ; hl = the count
.loop:  call    in_getc
        jr      c,.end
        cp      10
        jr      z,.end
        pop     bc
        push    bc
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      nc,.cut
        ld      (de),a
        inc     de
        inc     hl
        jr      .loop
.cut:   ld      a,1
        ld      (in_cut),a
.drop:  call    in_getc
        jr      c,.end
        cp      10
        jr      nz,.drop
.end:   push    af
        xor     a
        ld      (de),a
        pop     af
        pop     bc
        pop     de
        ld      b,h
        ld      c,l
        ret     nc                      ; a line ended by LF
        ld      a,b
        or      c
        scf
        ret     z                       ; the end, nothing read
        or      a                       ; the last line, without its LF
        ret
