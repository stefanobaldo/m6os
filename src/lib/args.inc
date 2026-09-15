; The arguments and the options. Needs err.inc.
;
;   arg_next    HL -> the next argument, CF clear; CF set when none is
;               left. The first call returns argv[1]. Corrupts AF, DE.
;   arg_peek    The same without taking it.
;   arg_opts    HL -> the option letters, DE -> the synopsis: takes every
;               leading argument that begins with '-' ("-" alone is an
;               argument; "--" ends the options and is taken). Letters may
;               be grouped, -ln; letter i of the string sets bit i of
;               opt_flags; a letter followed by ':' in the string takes a
;               value — the rest of the word, or the next argument — and
;               leaves its address in opt_val. An unknown letter, or a
;               missing value, is err_usage. Corrupts everything.
        define ARGS_INC

arg_peek:
        ld      hl,(arg_i)
        ld      de,(lib_argc)
        or      a
        sbc     hl,de
        jr      nc,.none
        ld      hl,(arg_i)
        add     hl,hl
        ld      de,(lib_argv)
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        or      a
        ret
.none:  scf
        ret

arg_next:
        call    arg_peek
        ret     c
        push    hl
        ld      hl,(arg_i)
        inc     hl
        ld      (arg_i),hl
        pop     hl
        or      a
        ret

arg_opts:
        ld      (opt_ltr),hl
        ld      (opt_use),de
.next:  call    arg_peek
        ret     c
        ld      a,(hl)
        cp      '-'
        ret     nz
        inc     hl
        ld      a,(hl)
        or      a
        ret     z                       ; "-" alone
        cp      '-'
        jr      nz,.word
        inc     hl
        ld      a,(hl)
        or      a
        jr      nz,.word0               ; "--x": letters from the x
        call    arg_next                ; "--": taken, the options end
        or      a
        ret
.word0: dec     hl
.word:  push    hl
        call    arg_next                ; the word is taken
        pop     hl
.letter:
        ld      a,(hl)
        or      a
        jr      z,.next
        push    hl
        call    opt_find
        pop     hl
        jr      c,.bad
        ld      a,(opt_flags)
        or      c
        ld      (opt_flags),a
        ld      a,b
        or      a
        jr      z,.more
        inc     hl                      ; a value: the rest of the word
        ld      a,(hl)
        or      a
        jr      nz,.value
        call    arg_next                ; or the next argument
        jr      c,.bad
.value: ld      (opt_val),hl
        jr      .next
.more:  inc     hl
        jr      .letter
.bad:   ld      de,(opt_use)
        jp      err_usage

; opt_find — A = a letter: C = its bit, B = 1 if it takes a value; CF set
; when it is not in the string.
opt_find:
        ld      e,a
        ld      hl,(opt_ltr)
        ld      c,1
.scan:  ld      a,(hl)
        or      a
        jr      z,.unknown
        cp      e
        jr      z,.found
        inc     hl
        ld      a,(hl)
        cp      ':'
        jr      nz,.shift
        inc     hl
.shift: rlc     c
        jr      .scan
.found: inc     hl
        ld      a,(hl)
        ld      b,0
        cp      ':'
        jr      nz,.novalue
        inc     b
.novalue:
        or      a
        ret
.unknown:
        scf
        ret
