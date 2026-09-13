; Shared definitions for a program that lives in a file and is started
; with exec: assembled for P0_PROG (build/<test>.progs/<name>, a raw
; image), it begins with the six-byte header the kernel checks. Include
; after kernel/kernel.inc.
;
;   m6_header pages     the header: jr start, "m6", the pages the program
;                       wants (1-3), a zero. The program's first
;                       instruction is at the label start.
;   m6_puts str         write the 0-terminated string at str to fd 1
;   m6_dec16, m6_atoi   a number out in decimal, digits in (in m6_proglib)
;   m6_proglib          the routines the macros call: put it after the
;                       program's code, before its data
;
; On entry BC = argc, HL = argv — a 0-terminated vector of pointers to
; 0-terminated strings, in the program's highest page under the kernel's
; frame — and SP is below it. A program that ends in ret exits with 0.
    macro m6_header pages
        org     P0_PROG
        jr      start
        db      "m6"
        db      pages
        db      0
    endm

    macro m6_puts str
        ld      hl,str
        call    m6_puts_hl
    endm

    macro m6_proglib
; m6_puts_hl — HL -> a 0-terminated string: written to fd 1. Corrupts
; everything.
m6_puts_hl:
        push    hl
        ld      bc,0
.len:   ld      a,(hl)
        or      a
        jr      z,.write
        inc     hl
        inc     bc
        jr      .len
.write: pop     hl
        ld      a,1
        sys     SYS_WRITE
        ret

; m6_dec16 — HL in decimal to fd 1, no leading zeros. Corrupts everything.
m6_dec16:
        ld      de,m6_decbuf+5
        xor     a
        ld      (de),a
.digit: ld      bc,10
        call    m6_div16                ; hl = hl / 10, a = the remainder
        add     a,'0'
        dec     de
        ld      (de),a
        ld      a,h
        or      l
        jr      nz,.digit
        ex      de,hl
        jp      m6_puts_hl
m6_decbuf:      ds 6

; m6_atoi — HL -> decimal digits: HL = their value, DE -> the first byte
; that is not a digit. No sign, no overflow check. Corrupts AF, BC.
m6_atoi:
        ex      de,hl
        ld      hl,0
.next:  ld      a,(de)
        sub     '0'
        ret     c
        cp      10
        ret     nc
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl
        add     hl,bc
        add     hl,hl                   ; * 10
        ld      c,a
        ld      b,0
        add     hl,bc
        inc     de
        jr      .next

; m6_div16 — HL = HL / BC, A = the remainder (BC < 256). Preserves BC, DE.
m6_div16:
        push    de
        ld      d,0
        ld      e,16
.bit:   add     hl,hl
        rl      d
        ld      a,d
        sub     c
        jr      c,.no
        ld      d,a
        inc     l
.no:    dec     e
        jr      nz,.bit
        ld      a,d
        pop     de
        ret
    endm
