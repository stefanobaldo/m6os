; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's body, its first part: the inner side of the door.
; Included by leg.asm at LEG_BODY, ahead of the file functions (legf.asm)
; and the entry (legi.asm). The body is in page 2 for the length of a
; call, over the program's own page 2, so an argument of the program's
; that lies there — a path, a file info block, a buffer to fill — cannot
; be seen from here. lb_call, which leg_body (leg.asm) calls with the
; registers the program's, reads the function's descriptor, has every
; pointer argument whose bytes meet 8000h-BFFFh copied into a staging
; buffer in page 3 (leg_stin) and hands the handler that buffer instead;
; on the way out it copies back what the function writes (leg_stout) and
; points a pointer that comes back — DE as it went in, which a program
; may count on, or _PARSE's into its string — at the program's own bytes
; again. An
; argument anywhere else is handed over as it came, which is nine calls
; in ten of the programs this was measured on. _EXPLAIN and its messages
; are here too: they need nothing of page 3.

; A descriptor: DE's kind in bits 0-2, HL's in bits 3-5, bit 6 when IX
; is a file info block, bit 7 when DE and HL come back as numbers
; (_FTIME's date and time) — otherwise one that comes back pointing into
; a staging buffer is a pointer into that argument: the register as it
; went in, or _PARSE's, _PFILE's and _WPATH's results. An FCB (legk.asm)
; is staged as a file info block: 64 bytes, in and out, which cover its
; 37 and _FREN's second name.
LK_PATH         equ 1           ; a string, or a file info block (FFh first)
LK_STR          equ 2           ; a string, 255 bytes at most
LK_OUT64        equ 3           ; 64 bytes to fill
LK_OUTB         equ 4           ; B bytes to fill
LK_OUT32        equ 5           ; 32 bytes to fill
LK_OUT11        equ 6           ; 11 bytes to fill
LK_FIB          equ 7           ; a file info block, read and filled
LD_IX           equ 40h
LD_NUM          equ 80h
; A slot's row: its staging buffer and size, then this call's.
LS_BUF          equ 0           ; 2
LS_SIZE         equ 2
LS_FLAGS        equ 3           ; bit 0: staged; bit 1: copied back
LS_PTR          equ 4           ; 2: the program's pointer
LS_LEN          equ 6           ; the bytes
LS_ROW          equ 7
; A kind's way in: leg_stin's mode, LM_OUT when it is copied back,
; LM_CLIP when the program's B is the length and must shrink with it.
LM_OUT          equ 80h
LM_CLIP         equ 40h

; lb_call — from leg_body: the body is in, interrupts are off, the
; registers are the program's and the handler is in leg_fn, its function
; in leg_fnum. Returns what the handler returned.
lb_call:
        ld      (lb_hl),hl
        ld      (lb_de),de
        push    af
        ld      a,b
        ld      (lb_b),a
        ld      a,(leg_fnum)
        cp      40h
        jr      c,.low
        sub     40h-32h                 ; 40h-70h follow 00h-31h
.low:   ld      e,a
        ld      d,0
        ld      hl,lb_desc
        add     hl,de
        ld      a,(hl)
        ld      (lb_d),a
        or      a
        jr      nz,.args
        pop     af                      ; no pointer to look at: straight in
        ld      de,(lb_de)
        ld      hl,(leg_fn)
        push    hl
        ld      hl,(lb_hl)
        ret
.args:  push    bc
        ld      (lb_ix),ix
        and     7
        ld      hl,(lb_de)
        ld      iy,lb_rde
        call    lb_stage
        ld      (lb_de),hl
        ld      a,(lb_d)
        rrca
        rrca
        rrca
        and     7
        ld      hl,(lb_hl)
        ld      iy,lb_rhl0
        call    lb_stage
        ld      (lb_hl),hl
        ld      a,(lb_d)
        and     LD_IX
        jr      z,.noix
        ld      a,LK_FIB
.noix:  ld      hl,(lb_ix)
        ld      iy,lb_rix
        call    lb_stage
        push    hl
        pop     ix
        pop     bc
        ld      a,(lb_b)                ; shrunk with a clipped buffer
        ld      b,a
        pop     af
        ld      hl,.back
        push    hl
        ld      hl,(leg_fn)
        push    hl
        ld      de,(lb_de)
        ld      hl,(lb_hl)
        ret                             ; into the handler
.back:  push    af
        ld      (lb_rhl),hl
        ld      (lb_rbc),bc
        push    de
        ld      iy,lb_rde
        call    lb_unstage
        ld      iy,lb_rhl0
        call    lb_unstage
        ld      iy,lb_rix
        call    lb_unstage
        pop     de
        ld      a,(lb_d)
        and     LD_NUM
        jr      nz,.out
        ld      iy,lb_rde               ; DE, then HL, against each
        call    lb_rebase               ; argument that was staged
        ld      iy,lb_rhl0
        call    lb_rebase
        push    de
        ld      de,(lb_rhl)
        ld      iy,lb_rde
        call    lb_rebase
        ld      iy,lb_rhl0
        call    lb_rebase
        ld      (lb_rhl),de
        pop     de
.out:   ld      hl,(lb_rhl)
        ld      bc,(lb_rbc)
        pop     af
        ret

; lb_stage — A = a kind, 0 for none, HL = the program's pointer, IY ->
; the slot's row: HL = the pointer the handler gets — the slot's staging
; buffer, the argument copied in, when its bytes meet page 2; as it came
; otherwise. Corrupts AF, BC, DE.
lb_stage:
        ld      (iy+LS_FLAGS),0
        or      a
        ret     z
        ld      (iy+LS_PTR),l
        ld      (iy+LS_PTR+1),h
        ld      e,a
        ld      d,0
        push    hl
        ld      hl,lb_modes
        add     hl,de
        ld      c,(hl)                  ; c = the way in
        ld      hl,lb_lens
        add     hl,de
        ld      a,(hl)                  ; a = the bytes; 0: the program's B
        pop     hl
        or      a
        jr      nz,.len
        ld      a,(lb_b)
        or      a
        ret     z
.len:   cp      (iy+LS_SIZE)
        jr      c,.fits
        ld      a,(iy+LS_SIZE)          ; no more than the buffer holds
        bit     6,c                     ; LM_CLIP: the function is told
        jr      z,.fits
        ld      (lb_b),a
.fits:  ld      (iy+LS_LEN),a
        ld      b,a
        ld      a,h
        cp      0C0h
        ret     nc                      ; in page 3, which is in view
        push    hl
        ld      e,b
        ld      d,0
        dec     de
        add     hl,de                   ; its last byte
        ld      a,h
        pop     hl
        cp      80h
        ret     c                       ; and it ends below page 2
        ld      a,c
        and     LM_OUT
        rlca
        rlca                            ; bit 1: copied back
        inc     a                       ; bit 0: staged
        ld      (iy+LS_FLAGS),a
        ld      e,(iy+LS_BUF)
        ld      d,(iy+LS_BUF+1)
        push    de
        ld      a,c
        and     3
        ld      c,b
        ld      b,0
        call    leg_stin
        pop     hl
        ret

; lb_unstage — IY -> a slot's row: what the function wrote there copied
; to the program's buffer, when the slot was staged and is one that is
; filled. Corrupts AF, BC, DE, HL.
lb_unstage:
        bit     1,(iy+LS_FLAGS)
        ret     z
        ld      l,(iy+LS_BUF)
        ld      h,(iy+LS_BUF+1)
        ld      e,(iy+LS_PTR)
        ld      d,(iy+LS_PTR+1)
        ld      c,(iy+LS_LEN)
        ld      b,0
        jp      leg_stout

; lb_rebase — DE = what the function returned in a register, IY -> a
; slot's row: when the slot was staged and DE points into its staging
; buffer — its end included, where a string's terminator may be — DE =
; the same place in the program's own argument. Corrupts AF, BC, HL.
lb_rebase:
        bit     0,(iy+LS_FLAGS)
        ret     z
        ld      l,(iy+LS_BUF)
        ld      h,(iy+LS_BUF+1)
        ld      b,h
        ld      c,l                     ; bc = the buffer
        dec     hl
        or      a
        sbc     hl,de
        ret     nc                      ; below it
        ld      l,(iy+LS_SIZE)
        ld      h,0
        add     hl,bc
        or      a
        sbc     hl,de
        ret     c                       ; above it
        ex      de,hl
        or      a
        sbc     hl,bc                   ; the offset in it
        ld      e,(iy+LS_PTR)
        ld      d,(iy+LS_PTR+1)
        add     hl,de
        ex      de,hl
        ret

lb_rde:         dw lb_sde
                db LB_SDE,0,0,0,0
lb_rhl0:        dw lb_shl
                db LB_SHL,0,0,0,0
lb_rix:         dw lb_six
                db 64,0,0,0,0
lb_lens:        db 0,128,255,64,0,32,11,64
lb_modes:       db 0,SI_PATH,SI_STR,SI_BLOCK|LM_OUT,SI_BLOCK|LM_OUT|LM_CLIP
                db SI_BLOCK|LM_OUT,SI_BLOCK|LM_OUT,SI_BLOCK|LM_OUT

; The descriptors, one a function: 00h-31h, then 40h-70h. A function of
; page 3's never comes here and reads 0.
lb_desc:
        ds      0Fh,0                                   ; 00h-0Eh
        db      LK_FIB, LK_FIB, LK_FIB                  ; 0Fh _FOPEN, 10h _FCLOSE,
                                                        ;   11h _SFIRST: the FCB
        db      LD_NUM                                  ; 12h _SNEXT: no argument
        db      LK_FIB                                  ; 13h _FDEL
        db      0,0                                     ; 14h, 15h: page 3's
        db      LK_FIB, LK_FIB                          ; 16h _FMAKE, 17h _FREN
        ds      9,0                                     ; 18h-20h
        db      0,0                                     ; 21h, 22h: page 3's
        db      LK_FIB                                  ; 23h _FSIZE
        ds      0Dh,0                                   ; 24h-30h
        db      LK_OUT32                                ; 31h _DPARM
        db      LK_PATH|LK_PATH<<3|LD_IX                ; 40h _FFIRST
        db      LD_IX                                   ; 41h _FNEXT
        db      LK_PATH|LK_PATH<<3|LD_IX                ; 42h _FNEW
        db      LK_PATH, LK_PATH                        ; 43h _OPEN, 44h _CREATE
        db      0,0,0,0,0,0,0                           ; 45h-4Bh
        db      LK_PATH, LK_PATH                        ; 4Ch _HTEST, 4Dh _DELETE
        db      LK_PATH|LK_PATH<<3, LK_PATH|LK_PATH<<3  ; 4Eh _RENAME, 4Fh _MOVE
        db      LK_PATH, LK_PATH|LD_NUM                 ; 50h _ATTR, 51h _FTIME
        db      0                                       ; 52h _HDELETE
        db      LK_PATH<<3, LK_PATH<<3                  ; 53h _HRENAME, 54h _HMOVE
        db      0,0,0,0                                 ; 55h-58h
        db      LK_OUT64                                ; 59h _GETCD
        db      LK_PATH                                 ; 5Ah _CHDIR
        db      LK_STR                                  ; 5Bh _PARSE
        db      LK_STR|LK_OUT11<<3                      ; 5Ch _PFILE
        db      0                                       ; 5Dh _CHKCHR
        db      LK_OUT64                                ; 5Eh _WPATH
        db      0,0,0,0,0,0,0                           ; 5Fh-65h
        db      LK_OUT64                                ; 66h _EXPLAIN
        db      0,0,0,0                                 ; 67h-6Ah
        db      LK_OUTB|LK_STR<<3                       ; 6Bh _GENV
        db      LK_STR|LK_STR<<3                        ; 6Ch _SENV
        db      LK_OUTB<<3                              ; 6Dh _FENV
        db      0,0,0                                   ; 6Eh-70h
        ASSERT  $-lb_desc == 32h+31h

; _EXPLAIN (66h): B = an error code, DE -> a 64-byte buffer: its message,
; 0-terminated, and B = 0 — or, for a code the layer has no words for,
; MSX-DOS 2's "User error n" below 40h and "System error n" from it, in
; decimal, and B as it came. The
; messages are not in the body: /bin/dos carries them, behind an index
; at LEG_MSGIX of the file (bin/dos.asm), and they are read from there
; on demand — an error's path, rare — into a buffer
; of the body's and copied from it, since the kernel reaches the body's
; buffers and not a program's page 3.
f_explain:
        push    de
        push    bc
        ld      hl,s_dosbin
        ld      a,O_RDONLY
        leg_sysx SYS_OPEN
        pop     bc
        pop     de
        jr      c,.none
        ld      a,l
        ld      (x_fd),a
        push    de
        push    bc
        ld      hl,LEG_MSGIX
        ld      bc,LEG_PATHMAX
        call    .seekread               ; the index
        jr      c,.close
        pop     bc
        push    bc
        ld      hl,leg_path2
.find:  ld      a,(hl)
        or      a
        jr      z,.close
        cp      b
        inc     hl
        jr      z,.at
        inc     hl
        inc     hl
        jr      .find
.at:    ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      bc,64
        call    .seekread
        jr      c,.close
        ld      a,(x_fd)
        leg_sysx SYS_CLOSE
        pop     bc
        pop     de
        xor     a
        ld      b,a
        ld      (leg_path2+63),a
        ld      hl,leg_path2
.copy:  ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.copy
        ret
.close: ld      a,(x_fd)
        leg_sysx SYS_CLOSE
        pop     bc
        pop     de
.none:  ld      hl,s_user
        ld      a,b
        cp      40h
        jr      c,.word
        ld      hl,s_system
.word:  ld      a,(hl)
        or      a
        jr      z,.digits
        ld      (de),a
        inc     hl
        inc     de
        jr      .word
.digits:                                ; the hundreds and the tens but
        ld      a,b                     ; a leading 0, then the units
        ld      c,100
        call    leg_digit
        ld      l,h
        ld      c,10
        call    leg_digit
        add     a,'0'
        ld      c,a
        ld      a,l
        cp      '0'
        jr      z,.nohun
        ld      (de),a
        inc     de
        jr      .tens
.nohun: ld      a,h
        cp      '0'
        jr      z,.units
.tens:  ld      a,h
        ld      (de),a
        inc     de
.units: ld      a,c
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        ret
; .seekread — HL = an offset in /bin/dos, BC = a count: as many bytes
; into leg_path2, fewer at the file's end. CF from the kernel.
.seekread:
        push    bc
        ld      de,0
        ld      b,SEEK_SET
        ld      a,(x_fd)
        leg_sysx SYS_LSEEK
        pop     bc
        ret     c
        ld      a,(x_fd)
        ld      hl,leg_path2
        leg_sysx SYS_READ
        ret
s_user:         db "User error ",0
s_system:       db "System error ",0
s_dosbin:       db "/bin/dos",0
