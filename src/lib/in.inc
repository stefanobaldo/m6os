; Buffered input from one descriptor: a 512-byte buffer on a 256-byte
; boundary, so a whole sector read from a file goes from the driver into
; it directly. On the keyboard in canonical mode a fill returns one line.
; A program that wants bytes or lines rather than blocks includes
; lib/line.inc after this.
;
;   in_open     A = the descriptor: the buffer emptied. Corrupts AF, HL.
;   in_fill     Reads up to 512 bytes: HL -> them, BC = how many, 0 at the
;               end; CF with A = the errno on an error. Corrupts everything.
        define IN_INC

in_open:
        ld      (in_fd),a
        ld      hl,in_buf
        ld      (in_ptr),hl
        ld      (in_end),hl
        ret

in_fill:
        ld      a,(in_fd)
        ld      hl,in_buf
        ld      bc,512
        sys     SYS_READ
        ret     c
        ld      b,h
        ld      c,l
        ld      hl,in_buf
        ld      (in_ptr),hl
        add     hl,bc
        ld      (in_end),hl
        ld      hl,in_buf
        or      a
        ret
