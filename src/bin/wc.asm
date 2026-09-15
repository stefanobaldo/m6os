; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; wc [-lwc] [file...] — lines, words and bytes of each file, in that
; order whatever the options' order, each right-aligned in seven columns,
; then the file's name; all three without options; descriptor 0 and no
; name without a file; a "total" line after more than one file.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,opts
        ld      de,usage
        call    arg_opts
        ld      a,(opt_flags)
        or      a
        jr      nz,.opted
        ld      a,7
        ld      (opt_flags),a
.opted: ld      hl,total
        ld      b,12
        call    zero
        xor     a
        ld      (nfiles),a
        call    arg_next
        jr      c,.stdin
.file:  ld      (name),hl
        xor     a
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    count
        ld      a,(fd)
        sys     SYS_CLOSE
        ld      hl,(name)
        call    report
        ld      hl,nfiles
        inc     (hl)
.next:  call    arg_next
        jr      nc,.file
        ld      a,(nfiles)
        cp      2
        jr      c,.done
        ld      hl,total
        ld      de,count_l
        ld      bc,12
        ldir                            ; the totals into the counts
        ld      hl,s_total
        call    report
.done:  ld      a,(lib_status)
        ret
.err:   ld      de,(name)
        call    err_file
        jr      .next
.stdin: xor     a
        ld      (fd),a
        call    count
        ld      hl,0
        call    report
        jr      .done

; count — the descriptor in fd read to its end into count_l, count_w,
; count_c, each added to its total.
count:  ld      hl,count_l
        ld      b,12
        call    zero
        xor     a
        ld      (inword),a
        ld      a,(fd)
        call    in_open
.loop:  call    in_getc
        jr      c,.end
        ld      hl,count_c
        call    inc32
        cp      10
        jr      nz,.notnl
        ld      hl,count_l
        call    inc32
.notnl: cp      ' '
        jr      z,.blank
        cp      9
        jr      z,.blank
        cp      10
        jr      z,.blank
        cp      13
        jr      z,.blank
        ld      a,(inword)
        or      a
        jr      nz,.loop
        ld      a,1
        ld      (inword),a
        ld      hl,count_w
        call    inc32
        jr      .loop
.blank: xor     a
        ld      (inword),a
        jr      .loop
.end:   ld      a,(in_err)
        or      a
        jr      z,.add
        ld      de,(name)
        call    err_file
.add:   ld      hl,count_l
        ld      de,total
        ld      b,3
.sum:   push    bc
        call    add32                   ; (de) += (hl); both advance 4
        pop     bc
        djnz    .sum
        ret

; report — HL -> a name (0: none): the selected counts, then the name.
report: push    hl
        ld      a,(opt_flags)
        ld      c,a                     ; bit 0 lines, 1 words, 2 bytes
        ld      hl,count_l
        ld      b,3
.each:  push    bc
        push    hl
        bit     0,c
        jr      z,.skip
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ex      de,hl                   ; de:hl = the count
        ld      b,7
        call    out_dec32
.skip:  pop     hl
        pop     bc
        ld      de,4
        add     hl,de
        rr      c
        djnz    .each
        pop     hl
        ld      a,h
        or      l
        jr      z,.nl
        ld      a,' '
        call    out_putc
        call    out_puts
.nl:    ld      a,10
        jp      out_putc

; zero — B bytes at HL zeroed.
zero:   ld      (hl),0
        inc     hl
        djnz    zero
        ret

; inc32 — the 32-bit number at HL incremented. Preserves A.
inc32:  inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret

; add32 — the 32-bit number at DE += the one at HL; both advanced past.
add32:  ld      b,4
        or      a
.byte:  ld      a,(de)
        adc     a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    .byte
        ret

opts:   db      "lwc",0
usage:  db      "wc [-lwc] [file...]",0
s_total: db     "total",0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/line.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     nfiles,1
        bss     inword,1
        bss     count_l,4
        bss     count_w,4
        bss     count_c,4
        bss     total,12
