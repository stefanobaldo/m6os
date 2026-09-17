; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; ls [-l] [path...] — the entries of each directory, sorted by name, one
; per line, . and .. left out; a path that names a file is listed alone;
; more than one path prints "path:" before each. -l puts the attributes,
; the size and the time before the name: d r h s a, a - for each clear
; bit; the size in ten columns; YYYY-MM-DD HH:MM as the entry has it.
; The entries fill a pool sized by the assembler from what is left of
; the page — nine fixed bytes and the name at its own length, each —
; sorted as they arrive by a binary search on a table of pointers; a
; directory with more entries than the pool or the table holds is listed
; as far as they go and then reported.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,opts
        ld      de,s_usage
        call    arg_opts
        ld      hl,(lib_argc)
        ld      de,(arg_i)
        or      a
        sbc     hl,de
        ld      (npaths),hl
        ld      a,h
        or      l
        jr      nz,.paths
        ld      hl,s_dot
        call    list
        jr      .done
.paths: xor     a
        ld      (notfirst),a
.loop:  call    arg_next
        jr      c,.done
        push    hl
        ld      hl,(npaths)
        dec     hl
        ld      a,h
        or      l
        jr      z,.one                  ; one path: no header
        ld      a,(notfirst)
        or      a
        jr      z,.head
        ld      a,10
        call    out_putc
.head:  ld      a,1
        ld      (notfirst),a
        pop     hl
        push    hl
        call    out_puts
        ld      a,':'
        call    out_putc
        ld      a,10
        call    out_putc
.one:   pop     hl
        call    list
        jr      .loop
.done:  ld      a,(lib_status)
        ret

; A pool entry: the record's fixed bytes, then the name, 0-terminated.
E_ATTR  equ     0
E_SIZE  equ     1                       ; 4
E_MTIME equ     5                       ; 4
E_NAME  equ     9
E_FIXED equ     9

; list — HL -> a path: a file printed as itself, a directory read, sorted
; and printed.
list:   ld      (path),hl
        ld      de,ent
        sys     SYS_STAT
        jr      c,.err
        ld      a,(ent+DE_ATTR)
        and     DA_DIR
        jr      nz,.dir
        ld      hl,pool
        ld      (next),hl
        ld      hl,(path)
        call    pack                    ; a file: its entry, the path as
        ld      hl,pool                 ; the name
        jp      print_ent
.err:   ld      de,(path)
        jp      err_file
.dir:   ld      hl,(path)
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        ld      hl,0
        ld      (count),hl
        ld      hl,pool
        ld      (next),hl
        xor     a
        ld      (over),a
.read:  ld      a,(fd)
        ld      hl,ent
        sys     SYS_READDIR
        jr      c,.rderr
        ld      a,h
        or      l
        jr      z,.end
        ld      hl,ent
        ld      a,(hl)
        cp      '.'
        jr      nz,.keep
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.read                 ; "."
        cp      '.'
        jr      nz,.keep
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.read                 ; ".."
.keep:  ld      hl,(count)
        ld      de,LS_PTRS
        or      a
        sbc     hl,de
        jr      z,.full                 ; the table is full
        ld      hl,ent+DE_NAME
        call    pack
        jr      c,.full                 ; so is the pool
        call    insert
        ld      hl,(count)
        inc     hl
        ld      (count),hl
        jr      .read
.full:  ld      a,1                     ; more than fits: listed so far
        ld      (over),a
.end:   ld      a,(fd)
        sys     SYS_CLOSE
        call    print_all
        ld      a,(over)
        or      a
        ret     z
        call    err_head
        ld      hl,(path)
        call    err_puts
        ld      hl,s_many
        call    err_puts
        ld      a,1
        ld      (lib_status),a
        ret
.rderr: push    af
        ld      a,(fd)
        sys     SYS_CLOSE
        pop     af
        jp      .err

; pack — the record in ent, HL -> the name to keep: a pool entry at
; next, which is left pointing at it; next moved past it. CF when the
; pool has no room for it, nothing written.
pack:   push    hl
        ld      bc,E_FIXED+1            ; the fixed bytes and the name's 0
.len:   ld      a,(hl)
        or      a
        jr      z,.gotlen
        inc     hl
        inc     bc
        jr      .len
.gotlen:
        ld      hl,POOL_END
        ld      de,(next)
        or      a
        sbc     hl,de                   ; the room
        or      a
        sbc     hl,bc
        pop     hl
        ret     c
        push    hl
        ld      de,(next)
        ld      (entry),de
        ld      a,(ent+DE_ATTR)
        ld      (de),a
        inc     de
        ld      hl,ent+DE_SIZE
        ld      bc,8                    ; the size, then the time
        ldir
        pop     hl
.copy:  ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.copy
        ld      (next),de
        or      a
        ret

; insert — the entry just packed into the pointer table, kept sorted by
; name: a binary search for the first entry that sorts after it, the
; pointers from there moved up one, the new one stored.
insert: ld      hl,0
        ld      (lo),hl
        ld      hl,(count)
        ld      (hi),hl
.search:
        ld      hl,(hi)
        ld      de,(lo)
        or      a
        sbc     hl,de
        jr      z,.place
        srl     h
        rr      l
        add     hl,de                   ; mid = lo + (hi - lo) / 2
        ld      (mid),hl
        add     hl,hl
        ld      de,ptrs
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de -> the entry at mid
        ld      hl,E_NAME
        add     hl,de
        ex      de,hl                   ; de -> its name
        ld      hl,(entry)
        ld      bc,E_NAME
        add     hl,bc                   ; hl -> the new name
        call    str_cmp                 ; CF when DE's sorts first
        jr      c,.right
        jr      z,.right                ; equal names go after
        ld      hl,(mid)
        ld      (hi),hl
        jr      .search
.right: ld      hl,(mid)
        inc     hl
        ld      (lo),hl
        jr      .search
.place: ld      hl,(count)
        ld      de,(lo)
        or      a
        sbc     hl,de
        jr      z,.store                ; at the end: nothing to move
        add     hl,hl
        ld      b,h
        ld      c,l                     ; bc = bytes to move
        ld      hl,(count)
        add     hl,hl
        ld      de,ptrs
        add     hl,de
        dec     hl                      ; hl -> the last byte in use
        ld      d,h
        ld      e,l
        inc     de
        inc     de                      ; de -> two bytes up
        lddr
.store: ld      hl,(lo)
        add     hl,hl
        ld      de,ptrs
        add     hl,de
        ld      de,(entry)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; print_all — the count entries, in the pointer table's order.
print_all:
        ld      hl,0
        ld      (idx),hl
.loop:  ld      hl,(idx)
        ld      de,(count)
        or      a
        sbc     hl,de
        ret     z
        ld      hl,(idx)
        add     hl,hl
        ld      de,ptrs
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl                   ; hl -> the entry
        call    print_ent
        ld      hl,(idx)
        inc     hl
        ld      (idx),hl
        jr      .loop

; print_ent — HL -> a pool entry: one line, the long form's columns first
; with -l.
print_ent:
        ld      (rec),hl
        ld      a,(opt_flags)
        bit     0,a
        jp      z,.name
        ld      c,(hl)                  ; E_ATTR
        ld      a,'d'
        bit     4,c
        call    flag
        ld      a,'r'
        bit     0,c
        call    flag
        ld      a,'h'
        bit     1,c
        call    flag
        ld      a,'s'
        bit     2,c
        call    flag
        ld      a,'a'
        bit     5,c
        call    flag
        ld      a,' '
        call    out_putc
        ld      hl,(rec)
        ld      de,E_SIZE
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ex      de,hl                   ; de:hl = the size
        ld      b,10
        call    out_dec32
        ld      a,' '
        call    out_putc
        ld      hl,(rec)
        ld      de,E_MTIME
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = the date word
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; bc = the time word
        ld      (tw),bc
        push    de
        ld      a,d
        srl     a                       ; the year since 1980
        ld      l,a
        ld      h,0
        ld      de,1980
        add     hl,de
        ld      b,0
        call    out_dec16
        ld      a,'-'
        call    out_putc
        pop     de
        push    de
        ld      a,e
        rrca
        rrca
        rrca
        rrca
        rrca
        and     7
        ld      c,a
        ld      a,d
        and     1
        add     a,a
        add     a,a
        add     a,a
        or      c                       ; the month
        call    dec2
        ld      a,'-'
        call    out_putc
        pop     de
        ld      a,e
        and     31                      ; the day
        call    dec2
        ld      a,' '
        call    out_putc
        ld      bc,(tw)
        ld      a,b
        srl     a
        srl     a
        srl     a                       ; the hour
        call    dec2
        ld      a,':'
        call    out_putc
        ld      bc,(tw)
        ld      a,c
        rrca
        rrca
        rrca
        rrca
        rrca
        and     7
        ld      e,a
        ld      a,b
        and     7
        add     a,a
        add     a,a
        add     a,a
        or      e                       ; the minute
        call    dec2
        ld      a,' '
        call    out_putc
.name:  ld      hl,(rec)
        ld      de,E_NAME
        add     hl,de
        call    out_puts
        ld      a,10
        jp      out_putc

; flag — A = a letter, printed when the bit tested was set, - otherwise.
flag:   jr      nz,.on
        ld      a,'-'
.on:    jp      out_putc

; dec2 — A = 0 to 99, two digits.
dec2:   ld      c,'0'-1
.tens:  inc     c
        sub     10
        jr      nc,.tens
        add     a,10
        push    af
        ld      a,c
        call    out_putc
        pop     af
        add     a,'0'
        jp      out_putc

opts:    db     "l",0
s_usage: db     "ls [-l] [path...]",0
s_dot:   db     ".",0
s_many:  db     ": too many entries",10,0

        include "lib/out.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     path,2
        bss     npaths,2
        bss     notfirst,1
        bss     fd,1
        bss     count,2
        bss     next,2
        bss     entry,2
        bss     over,1
        bss     lo,2
        bss     hi,2
        bss     mid,2
        bss     idx,2
        bss     rec,2
        bss     tw,2
        bss     ent,DIRENT_SIZE
LS_PTRS equ     512                     ; entries the table holds: a root's
        bss     ptrs,LS_PTRS*2
POOL_END equ    P0_TOP
        assert  POOL_END-__bss >= 8192  ; the pool: 8K at the least
        bss     pool,POOL_END-__bss
