; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; What a program started under Nextor does before the takeover, shared by
; the product loader: the console through the BDOS, the driver behind the
; current drive, the capture, the mem= argument. The including file
; defines nb_rec, the address of its KREC_SIZE-byte record, and includes
; nextor/abi2.asm, nextor/capture.asm and loader/takeover.asm beside this.
;
;   nb_puts     DE -> a '$'-terminated string, printed
;   nb_putc     A printed;  nb_newline;  nb_puthex8, nb_puthex16 (A, HL);
;   nb_putdec   A in decimal
;   nb_find     the driver behind the current drive into the record's
;               KR_DRV and KR_FIRST, the drive into nb_drive: A = 0, or
;               an NXE_* or BDOS code
;   nb_capture  the record filled from Nextor's RAM: A = 0, or 0F6h with
;               no driver in the table
;   nb_mem      mem=<K> on the command line into KR_MEMCAP: CF clear, or
;               CF with A = 0F9h (below 128), 0FAh (not a number), 0FBh
;               (not a multiple of 16)
; All corrupt everything.

NB_STROUT   equ 09h
NB_CURDRV   equ 19h
NB_CMDLINE  equ 0080h           ; DOS: a length byte, the string, a NUL

nb_puts:
        ld      c,NB_STROUT
        jp      BDOS

nb_putc:
        push    hl
        push    de
        push    bc
        ld      (nb_chbuf),a
        ld      de,nb_chbuf
        call    nb_puts
        pop     bc
        pop     de
        pop     hl
        ret

nb_newline:
        ld      a,13
        call    nb_putc
        ld      a,10
        jp      nb_putc

nb_puthex16:
        ld      a,h
        call    nb_puthex8
        ld      a,l
nb_puthex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,nb_putc
        add     a,'A'-'9'-1
        jr      nb_putc

nb_putdec:
        ld      l,a
        ld      h,0
        xor     a
        ld      (nb_leading),a
        ld      de,100
        call    .digit
        ld      de,10
        call    .digit
        ld      a,l
        add     a,'0'
        jp      nb_putc
.digit: ld      a,'0'-1
.sub:   inc     a
        or      a
        sbc     hl,de
        jr      nc,.sub
        add     hl,de
        cp      '0'
        jr      nz,.emit
        push    af
        ld      a,(nb_leading)
        or      a
        jr      nz,.zero
        pop     af
        ret
.zero:  pop     af
.emit:  ld      (nb_leading),a
        jp      nb_putc

nb_find:
        ld      c,NB_CURDRV
        call    BDOS
        ld      (nb_drive),a
        ld      ix,nb_rec+KR_DRV
        ld      hl,KT_SCRATCH
        call    nx_find
        or      a
        ret     nz
        ld      (nb_rec+KR_FIRST),hl
        ld      (nb_rec+KR_FIRST+2),de
        ret

nb_capture:
        ld      ix,nb_rec
        call    nx_capture
        ld      a,(nb_rec+KR_NDRV)
        or      a
        ld      a,0F6h
        ret     z
        xor     a
        ret

nb_mem:
        xor     a
        ld      (nb_rec+KR_MEMCAP),a
        ld      hl,NB_CMDLINE
        ld      b,(hl)                  ; length
        inc     hl
.scan:  ld      a,b
        cp      4
        jr      c,.absent               ; "mem=" no longer fits
        ld      a,(hl)
        and     0DFh                    ; upper case
        cp      'M'
        jr      nz,.next
        inc     hl
        ld      a,(hl)
        and     0DFh
        cp      'E'
        dec     hl
        jr      nz,.next
        inc     hl
        inc     hl
        ld      a,(hl)
        and     0DFh
        cp      'M'
        dec     hl
        dec     hl
        jr      nz,.next
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        cp      '='
        jr      z,.number
        dec     hl
        dec     hl
        dec     hl
.next:  inc     hl
        dec     b
        jr      .scan
.absent:
        or      a                       ; CF clear: no cap
        ret
.number:
        inc     hl                      ; hl -> the digits
        ld      de,0                    ; de = K
        ld      c,0                     ; c = digits seen
.digit: ld      a,(hl)
        sub     '0'
        jr      c,.end
        cp      10
        jr      nc,.end
        inc     c
        inc     hl
        push    hl
        ld      hl,6553
        or      a
        sbc     hl,de                   ; de > 6553 would overflow times 10
        pop     hl
        jr      c,.overflow
        push    hl
        ld      h,d
        ld      l,e
        add     hl,hl                   ; 2 K
        add     hl,hl                   ; 4 K
        add     hl,de                   ; 5 K
        add     hl,hl                   ; 10 K
        ld      e,a
        ld      d,0
        add     hl,de                   ; + the digit
        ex      de,hl
        pop     hl
        jr      .digit
.overflow:
        ld      c,0                     ; treated as not a number
.end:   ld      a,c
        or      a
        ld      a,0FAh                  ; not a number
        scf
        ret     z
        ld      a,e
        and     0Fh
        ld      a,0FBh                  ; not a multiple of 16
        scf
        ret     nz
        ld      hl,128
        ex      de,hl
        or      a
        sbc     hl,de                   ; K - 128
        ld      a,0F9h                  ; below the floor
        ret     c
        add     hl,de                   ; hl = K
        ld      de,4096
        or      a
        sbc     hl,de
        jr      nc,.nocap               ; 4096 and above: no cap
        add     hl,de
        srl     h                       ; K / 16 = segments (K < 4096: fits)
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      a,l
        ld      (nb_rec+KR_MEMCAP),a
.nocap: or      a
        ret

nb_chbuf:   db  0,'$'
nb_leading: db  0
nb_drive:   db  0
