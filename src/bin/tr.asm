; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; tr set1 set2 — descriptor 0 to the output, each byte of set1 replaced
; by the byte at the same place in set2, every other byte as it is.
; a-z in a set is the range; \n, \t and \\ are the byte named, and a \
; before any other byte is that byte. A set2 shorter than set1 repeats
; its last byte; a longer one has its excess ignored.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,usage
        ld      (s1),hl
        call    arg_next
        jr      c,usage
        ld      (s2),hl
        call    arg_next
        jr      nc,usage
        ld      hl,tab                  ; every byte itself
        xor     a
.id:    ld      (hl),a
        inc     l
        inc     a
        jr      nz,.id
        ld      hl,(s1)
        ld      de,e1
        call    expand
        ld      (n1),bc
        ld      hl,(s2)
        ld      de,e2
        call    expand
        ld      a,b
        or      c
        jr      z,usage                 ; nothing to replace with
        ld      hl,e2
        add     hl,bc
        dec     hl
        ld      (e2last),hl
        ld      hl,e1
        ld      de,e2
        ld      bc,(n1)
.map:   ld      a,b
        or      c
        jr      z,copy
        ld      a,(hl)
        push    hl
        ld      h,tab>>8
        ld      l,a
        ld      a,(de)
        ld      (hl),a
        pop     hl
        inc     hl
        dec     bc
        push    hl
        ld      hl,(e2last)
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.map                  ; set2's last byte: kept
        inc     de
        jr      .map
usage:  ld      de,s_usage
        jp      err_usage

; copy — descriptor 0 through the table to the output, a flush after
; each read.
copy:   xor     a
        call    in_open
.loop:  call    in_fill
        jr      c,.rerr
        ld      a,b
        or      c
        jr      z,.done
        push    hl
        push    bc
.byte:  ld      a,(hl)
        push    hl
        ld      h,tab>>8
        ld      l,a
        ld      a,(hl)
        pop     hl
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.byte
        pop     bc
        pop     hl
        call    out_write
        call    out_flush
        jr      .loop
.done:  xor     a
        ret
.rerr:  ld      de,0
        call    err_file
        ld      a,1
        ret

; expand — HL -> a set as typed, DE -> where its bytes go: BC = how
; many. More than 256 is usage.
expand: ld      bc,0
.next:  ld      a,(hl)
        or      a
        ret     z
        inc     hl
        cp      '\'
        jr      nz,.byte
        ld      a,(hl)
        or      a
        jr      z,.bs                   ; a \ at the end: itself
        inc     hl
        cp      'n'
        jr      nz,.t
        ld      a,10
        jr      .one
.t:     cp      't'
        jr      nz,.one                 ; \\ and any other: the byte itself
        ld      a,9
        jr      .one
.bs:    ld      a,'\'
        jr      .one
.byte:  ex      af,af'
        ld      a,(hl)
        cp      '-'
        jr      nz,.single
        inc     hl
        ld      a,(hl)
        or      a
        jr      nz,.range
        dec     hl                      ; a - at the end: a byte of its own
.single:
        ex      af,af'
.one:   call    put
        jr      .next
.range: inc     hl
        ld      (rend),a
        ex      af,af'                  ; a = the first byte
        push    hl
        ld      hl,rend
        cp      (hl)
        pop     hl
        jr      z,.one                  ; a-a
        jr      nc,usage                ; z-a
.rl:    call    put
        push    hl
        ld      hl,rend
        cp      (hl)
        pop     hl
        jr      z,.next
        inc     a
        jr      .rl

; put — A = a byte into the set at DE, BC counted.
put:    push    af
        ld      a,b
        or      a
        jr      nz,.long
        pop     af
        ld      (de),a
        inc     de
        inc     bc
        ret
.long:  pop     af
        jp      usage

s_usage: db     "tr set1 set2",0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     s1,2
        bss     s2,2
        bss     n1,2
        bss     e2last,2
        bss     rend,1
        bss     e1,256
        bss     e2,256
        bss_align
        bss     tab,256
