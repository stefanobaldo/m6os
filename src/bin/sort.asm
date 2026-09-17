; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; sort [file...] — the lines of the files, or of descriptor 0, in byte
; order. Everything is read into the page: the text grows up from the
; end of the program, and a table of pointers to the lines grows down
; from the top of the page, with room kept below it for a second table
; of the same size; when the two would meet the input is too large, and
; nothing is printed. The pointers are sorted by a bottom-up merge sort
; between the two tables — N log N compares, no pointer ever moved more
; than once a pass — and the lines printed in their order.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,text
        ld      (dend),hl
        ld      (cur),hl
        ld      (scanp),hl
        ld      hl,0
        ld      (n),hl
        call    arg_next
        jr      c,.stdin
.file:  ld      (name),hl
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    slurp
        push    af
        ld      a,(fd)
        sys     SYS_CLOSE
        pop     af
        jr      c,.err
.next:  call    arg_next
        jr      nc,.file
.done:  call    finish
        call    msort
        call    print
        ld      a,(lib_status)
        ret
.err:   ld      de,(name)
        call    err_file
        jr      .next
.stdin: xor     a
        ld      (fd),a
        ld      hl,0
        ld      (name),hl
        call    slurp
        jr      nc,.done
        ld      de,(name)
        call    err_file
        jr      .done

; slurp — the descriptor in fd read to its end after the text so far,
; in pieces of at most 4 KB, each scanned for its lines. CF with A =
; the errno when a read fails.
slurp:  ld      hl,(n)
        add     hl,hl
        add     hl,hl
        ex      de,hl
        ld      hl,TOP
        or      a
        sbc     hl,de                   ; hl = the top less the tables
        ld      de,(dend)
        or      a
        sbc     hl,de                   ; hl = the room
        jp      c,toolarge
        ld      de,8
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jp      c,toolarge              ; too little for a line and its pointer
        ld      de,4096
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.size
        ld      hl,4096
.size:  ld      b,h
        ld      c,l
        ld      a,(fd)
        ld      hl,(dend)
        sys     SYS_READ
        ret     c
        ld      a,h
        or      l
        ret     z                       ; the end: CF clear
        ld      de,(dend)
        add     hl,de
        ld      (dend),hl
        call    scan
        jr      slurp

; scan — the bytes from scanp to dend: each LF becomes a 0 and the line
; before it enters the table.
scan:   ld      hl,(scanp)
.loop:  ld      de,(dend)
        or      a
        sbc     hl,de
        jr      z,.end
        add     hl,de
        ld      a,(hl)
        cp      10
        jr      nz,.byte
        ld      (hl),0
        push    hl
        ld      hl,(dend)
        call    store
        pop     hl
        inc     hl
        ld      (cur),hl
        jr      .loop
.byte:  inc     hl
        jr      .loop
.end:   ld      hl,(dend)
        ld      (scanp),hl
        ret

; store — HL = the end of the data: the line at cur enters the table, at
; the top less 2 (n + 1), after the check that both tables fit above HL.
store:  push    hl
        ld      hl,(n)
        inc     hl
        add     hl,hl
        add     hl,hl
        ex      de,hl
        ld      hl,TOP
        or      a
        sbc     hl,de                   ; hl = the top less 4 (n + 1)
        pop     de
        or      a
        sbc     hl,de
        jp      c,toolarge
        ld      hl,(n)
        inc     hl
        ld      (n),hl
        add     hl,hl
        ex      de,hl
        ld      hl,TOP
        or      a
        sbc     hl,de                   ; hl -> the new entry
        ld      de,(cur)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; finish — a last line without its LF gets a 0 and enters the table.
finish: ld      hl,(dend)
        ld      de,(cur)
        or      a
        sbc     hl,de
        ret     z
        ld      hl,(dend)
        ld      (hl),0
        inc     hl
        ld      (dend),hl
        jp      store

toolarge:
        ld      de,s_large
        call    err_msg
        ld      a,1
        jp      lib_exit

; msort — the n pointers, in the table that ends at TOP, sorted: runs of
; width 1, 2, 4, ... merged from one table into the other, the tables
; swapping each pass; src names the sorted one at the end.
msort:  ld      hl,(n)
        add     hl,hl
        ex      de,hl
        ld      hl,TOP
        or      a
        sbc     hl,de
        ld      (src),hl
        or      a
        sbc     hl,de
        ld      (dst),hl
        ld      hl,1
        ld      (w),hl
.pass:  ld      hl,(w)
        ld      de,(n)
        or      a
        sbc     hl,de
        ret     nc                      ; one run of everything: sorted
        ld      hl,0
        ld      (ri),hl
.run:   ld      hl,(ri)
        ld      de,(n)
        or      a
        sbc     hl,de
        jr      nc,.swap
        ld      hl,(ri)
        ld      de,(w)
        add     hl,de
        call    minn
        ld      (m1),hl
        ld      de,(w)
        add     hl,de
        call    minn
        ld      (m2),hl
        ld      hl,(ri)
        add     hl,hl
        ld      de,(src)
        add     hl,de
        ld      (lp),hl
        ld      hl,(ri)
        add     hl,hl
        ld      de,(dst)
        add     hl,de
        ld      (o),hl
        ld      hl,(m1)
        add     hl,hl
        ld      de,(src)
        add     hl,de
        ld      (lend),hl
        ld      (rp),hl
        ld      hl,(m2)
        add     hl,hl
        ld      de,(src)
        add     hl,de
        ld      (rend),hl
        call    merge
        ld      hl,(m2)
        ld      (ri),hl
        jr      .run
.swap:  ld      hl,(src)
        ld      de,(dst)
        ld      (src),de
        ld      (dst),hl
        ld      hl,(w)
        add     hl,hl
        ld      (w),hl
        jp      .pass

; minn — HL = the smaller of HL and n.
minn:   ld      de,(n)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        ret     c
        ld      hl,(n)
        ret

; merge — the runs l..lend and r..rend into o, the earlier line first
; and the left one when they are equal.
merge:  ld      hl,(lp)
        ld      de,(lend)
        or      a
        sbc     hl,de
        jr      z,.restr
        ld      hl,(rp)
        ld      de,(rend)
        or      a
        sbc     hl,de
        jr      z,.restl
        ld      hl,(lp)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        push    de
        ld      hl,(rp)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl                      ; hl -> the left line, de -> the right
        call    str_cmp                 ; CF when DE's sorts first
        jr      c,.takr
        ld      hl,(lp)
        call    emit
        ld      (lp),hl
        jr      merge
.takr:  ld      hl,(rp)
        call    emit
        ld      (rp),hl
        jr      merge
.restr: ld      hl,(rp)
        ld      de,(rend)
        jr      .rest
.restl: ld      hl,(lp)
        ld      de,(lend)
.rest:  ex      de,hl
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = the bytes left in the run
        ex      de,hl
        ld      a,b
        or      c
        ret     z
        ld      de,(o)
        ldir
        ld      (o),de
        ret

; emit — HL -> an entry: copied to o; both advanced.
emit:   ld      de,(o)
        ldi
        ldi
        ld      (o),de
        ret

; print — the n lines in the sorted table's order, an LF after each.
print:  ld      hl,(n)
        ld      (ri),hl
        ld      hl,(src)
.loop:  ld      de,(ri)
        ld      a,d
        or      e
        ret     z
        dec     de
        ld      (ri),de
        push    hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        call    out_puts
        ld      a,10
        call    out_putc
        pop     hl
        inc     hl
        inc     hl
        jr      .loop

TOP      equ    P0_TOP
s_large: db     "input too large",0

        include "lib/out.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     dend,2
        bss     cur,2
        bss     scanp,2
        bss     n,2
        bss     src,2
        bss     dst,2
        bss     w,2
        bss     ri,2
        bss     m1,2
        bss     m2,2
        bss     lp,2
        bss     lend,2
        bss     rp,2
        bss     rend,2
        bss     o,2
        bss_align
text     equ    __bss
SORT_CAP equ    (TOP-text)/26           ; lines of 22 bytes, with their pointers
        assert  SORT_CAP >= 400
