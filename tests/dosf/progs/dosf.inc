; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Shared by the raw .COM programs of tests/dosf: MSX-DOS 2 programs, no
; m6 header, the system through CALL 5. Each runs its steps and prints
; "<name> ok", or "<name> fail <step> code <hex>" and ends with the step
; as its code, which the shell prints.
BDOS        equ 0005h
_TERM0      equ 00h
_CONOUT     equ 02h
_STROUT     equ 09h
_DSKRST     equ 0Dh
_SELDSK     equ 0Eh
_LOGIN      equ 18h
_CURDRV     equ 19h
_SETDTA     equ 1Ah
_ALLOC      equ 1Bh
_GDATE      equ 2Ah
_SDATE      equ 2Bh
_GTIME      equ 2Ch
_VERIFY     equ 2Eh
_DPARM      equ 31h
_FFIRST     equ 40h
_FNEXT      equ 41h
_FNEW       equ 42h
_OPEN       equ 43h
_CREATE     equ 44h
_CLOSE      equ 45h
_ENSURE     equ 46h
_DUP        equ 47h
_READ       equ 48h
_WRITE      equ 49h
_SEEK       equ 4Ah
_IOCTL      equ 4Bh
_HTEST      equ 4Ch
_DELETE     equ 4Dh
_RENAME     equ 4Eh
_MOVE       equ 4Fh
_ATTR       equ 50h
_FTIME      equ 51h
_HDELETE    equ 52h
_HRENAME    equ 53h
_HMOVE      equ 54h
_HATTR      equ 55h
_HFTIME     equ 56h
_GETDTA     equ 57h
_GETVFY     equ 58h
_GETCD      equ 59h
_CHDIR      equ 5Ah
_PARSE      equ 5Bh
_PFILE      equ 5Ch
_CHKCHR     equ 5Dh
_WPATH      equ 5Eh
_FLUSH      equ 5Fh
_FORK       equ 60h
_JOIN       equ 61h
_TERM       equ 62h
_DEFER      equ 64h
_ERROR      equ 65h
_EXPLAIN    equ 66h
_ASSIGN     equ 6Ah
_GENV       equ 6Bh
_SENV       equ 6Ch
_FENV       equ 6Dh
_DSKCHK     equ 6Eh
_DOSVER     equ 6Fh
_REDIR      equ 70h
D_IBDOS     equ 0DCh
D_ISBFN     equ 0B8h
D_IDRV      equ 0DBh
D_IFNM      equ 0DAh
D_IPATH     equ 0D9h
D_NOFIL     equ 0D7h
D_NODIR     equ 0D6h
D_DUPF      equ 0D3h
D_DIRE      equ 0D2h
D_FILRO     equ 0D1h
D_DIRNE     equ 0D0h
D_IATTR     equ 0CFh
D_DOT       equ 0CEh
D_FILEX     equ 0CBh
D_FOPEN     equ 0CAh
D_EOF       equ 0C7h
D_ACCV      equ 0C6h
D_IPROC     equ 0C5h
D_NHAND     equ 0C4h
D_IHAND     equ 0C3h
D_IENV      equ 0C0h
D_ELONG     equ 0BFh
D_NORAM     equ 0DEh
JIFFY       equ 0FC9Eh

    macro d_puts str
        ld      de,str
        ld      c,_STROUT
        call    BDOS
    endm
    macro d_fn n
        ld      c,n
        call    BDOS
    endm
    macro d_step n
        ld      a,n
        ld      (t_step),a
    endm
; d_ok — the call must have answered 0. d_err code — it must have
; answered the code. d_hlis n — HL must be n.
    macro d_ok
        or      a
        jp      nz,t_fail
    endm
    macro d_err code
        cp      code
        jp      nz,t_fail
    endm
    macro d_hlis n
        ld      de,n
        or      a
        sbc     hl,de
        jp      nz,t_fail
    endm
; d_lib name — the epilogue: t_ok, t_fail, t_step, d_streq, d_memeq,
; d_dec16, d_hex8.
    macro d_lib Q1
t_ok:   d_puts  s_name
        d_puts  s_ok
        ld      c,_TERM0
        call    BDOS
t_fail: push    af
        d_puts  s_name
        d_puts  s_fail
        ld      a,(t_step)
        ld      l,a
        ld      h,0
        call    d_dec16
        d_puts  s_code
        pop     af
        call    d_hex8
        d_puts  s_crlf
        ld      a,(t_step)
        ld      b,a
        ld      c,_TERM
        call    BDOS
; d_streq — HL, DE -> 0-terminated strings: Z when equal.
d_streq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      d_streq
; d_memeq — HL, DE -> BC bytes: Z when equal.
d_memeq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,d_memeq
        ret
; d_dec16 — HL in decimal through _CONOUT.
d_dec16:
        ld      de,d_buf+5
        xor     a
        ld      (de),a
.digit: ld      bc,10
        call    d_div16
        add     a,'0'
        dec     de
        ld      (de),a
        ld      a,h
        or      l
        jr      nz,.digit
.out:   ld      a,(de)
        or      a
        ret     z
        push    de
        ld      e,a
        ld      c,_CONOUT
        call    BDOS
        pop     de
        inc     de
        jr      .out
d_div16:
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
; d_hex8 — A in hex through _CONOUT.
d_hex8: push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,.put
        add     a,7
.put:   push    af
        ld      e,a
        ld      c,_CONOUT
        call    BDOS
        pop     af
        ret
d_buf:  ds      6
t_step: db      0
s_name: db      Q1,"$"
s_ok:   db      " ok",13,10,"$"
s_fail: db      " fail $"
s_code: db      " code $"
s_crlf: db      13,10,"$"
    endm
