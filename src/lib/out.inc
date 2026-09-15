; Buffered output to descriptor 1: one 512-byte buffer on a 256-byte
; boundary, so a whole sector written to a file goes from the buffer to
; the driver, and a write into a pipe fills two rounds instead of three.
; Flushed when full, by lib_exit, and by out_flush. A program that copies
; its input to its output flushes after each read, so a line typed at the
; keyboard comes back at once.
;
;   out_putc    A = the byte. Preserves BC, DE, HL.
;   out_puts    HL -> a 0-terminated string. Corrupts AF, HL.
;   out_write   HL -> bytes, BC = how many. Corrupts everything.
;   out_dec16   HL = a number, B = a width to pad to with blanks (0: none).
;   out_dec32   DE:HL = a number, B = the width. Both corrupt everything.
;   out_flush   Corrupts everything.
; A write that fails ends the program through err_out: a message and
; status 1 with err.inc included, status 1 alone without it.
        define OUT_INC

out_putc:
        push    hl
        ld      hl,(out_ptr)
        ld      (hl),a
        inc     hl
        ld      (out_ptr),hl
        ld      a,h
        cp      high (out_buf+512)      ; full: the buffer is aligned
        pop     hl
        ret     nz
        push    bc
        push    de
        push    hl
        call    out_flush
        pop     hl
        pop     de
        pop     bc
        ret

out_puts:
.loop:  ld      a,(hl)
        or      a
        ret     z
        call    out_putc
        inc     hl
        jr      .loop

out_write:
.loop:  ld      a,b
        or      c
        ret     z
        push    bc                      ; the count
        push    hl                      ; the source
        ld      hl,out_buf+512
        ld      de,(out_ptr)
        or      a
        sbc     hl,de                   ; hl = the room, 1 to 512
        or      a
        sbc     hl,bc
        add     hl,bc                   ; CF: less room than bytes
        jr      c,.round
        ld      h,b
        ld      l,c                     ; else the whole count
.round: ld      b,h
        ld      c,l                     ; bc = this round
        pop     hl                      ; hl = the source
        ex      (sp),hl                 ; hl = the count, (sp) = the source
        or      a
        sbc     hl,bc                   ; hl = what is left after the round
        ex      (sp),hl                 ; hl = the source, (sp) = what is left
        ldir                            ; de = the new pointer
        ld      (out_ptr),de
        pop     bc                      ; bc = what is left
        ld      a,d
        cp      high (out_buf+512)
        jr      nz,.loop
        push    bc
        push    hl
        call    out_flush
        pop     hl
        pop     bc
        jr      .loop

out_flush:
        ld      hl,(out_ptr)
        ld      de,out_buf
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = the length
        ld      a,b
        or      c
        ret     z
        ld      hl,out_buf
        ld      (out_ptr),hl
        ld      a,1
        sys     SYS_WRITE
        jp      c,err_out
        ret

out_dec16:
        ld      de,0
out_dec32:
        push    bc                      ; b = the width
        ld      ix,out_num+11
        xor     a
        ld      (ix+0),a
.digit: call    out_div10
        add     a,'0'
        dec     ix
        ld      (ix+0),a
        ld      a,d
        or      e
        or      h
        or      l
        jr      nz,.digit
        pop     bc
        push    ix
        pop     de                      ; de -> the digits
        ld      hl,out_num+11
        or      a
        sbc     hl,de
        ld      c,l                     ; c = how many, 1 to 10
        ex      de,hl                   ; hl -> the digits
        ld      a,b
        or      a
        jr      z,.out
        sub     c
        jr      z,.out
        jr      c,.out
        ld      b,a
.blank: ld      a,' '
        call    out_putc
        djnz    .blank
.out:   jp      out_puts

; out_div10 — DE:HL = DE:HL / 10, A = the remainder. Preserves BC.
out_div10:
        push    bc
        ld      b,32
        xor     a
.bit:   add     hl,hl
        rl      e
        rl      d
        rla
        cp      10
        jr      c,.no
        sub     10
        inc     l
.no:    djnz    .bit
        pop     bc
        ret
