; hello — the program exec runs: with argv = /bin/hello one two it prints
; a line and exits with 7; a wrong argc or argv exits with 1, 2 or 3.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,b
        or      a
        jr      nz,.bad1
        ld      a,c
        cp      3
        jr      nz,.bad1
        push    hl
        ld      de,(hl)
        ex      de,hl
        ld      de,s_arg0
        call    streq
        jr      nz,.bad2
        pop     hl
        inc     hl
        inc     hl
        push    hl
        ld      de,(hl)
        ex      de,hl
        ld      de,s_arg1
        call    streq
        jr      nz,.bad2
        pop     hl
        inc     hl
        inc     hl
        push    hl
        ld      de,(hl)
        ex      de,hl
        ld      de,s_arg2
        call    streq
        jr      nz,.bad2
        pop     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        inc     hl
        or      (hl)
        jr      nz,.bad3                ; not 0-terminated
        m6_puts s_hello
        ld      a,7
        sys     SYS_EXIT
.bad1:  ld      a,1
        sys     SYS_EXIT
.bad2:  ld      a,2
        sys     SYS_EXIT
.bad3:  ld      a,3
        sys     SYS_EXIT

; streq — the strings at HL and DE: Z if equal.
streq:  ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      streq

        m6_proglib
s_arg0: db      "/bin/hello",0
s_arg1: db      "one",0
s_arg2: db      "two",0
s_hello: db     "hello from exec",10,0
