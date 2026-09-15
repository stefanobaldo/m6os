; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; mv old new, mv old... dir — each source renamed, within one volume; a
; destination that is a directory takes the source's last component.
; Across volumes the kernel answers EXDEV, reported with the new name;
; nothing is copied.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,(lib_argc)
        ld      de,3
        or      a
        sbc     hl,de
        jr      c,usage
        inc     hl
        ld      (left),hl
        ld      hl,(lib_argc)
        dec     hl
        add     hl,hl
        ld      de,(lib_argv)
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (dst),de
        xor     a
        ld      (todir),a
        ex      de,hl
        call    path_isdir
        jr      c,.absent
        jr      nz,.file
        ld      a,1
        ld      (todir),a
        jr      .loop
.absent:
        cp      E_NOENT
        jr      nz,.dsterr
.file:  ld      hl,(left)
        dec     hl
        ld      a,h
        or      l
        jr      z,.loop
        ld      a,E_NOTDIR
.dsterr:
        ld      de,(dst)
        call    err_file
        ld      a,1
        ret
.loop:  call    arg_next
        jr      c,.done
        call    move
        ld      hl,(left)
        dec     hl
        ld      (left),hl
        ld      a,h
        or      l
        jr      nz,.loop
.done:  ld      a,(lib_status)
        ret
usage:  ld      de,s_usage
        jp      err_usage

; move — HL -> a source: renamed to dst, or into it when it is a directory.
move:   ld      (src),hl
        ld      hl,(dst)
        ld      a,(todir)
        or      a
        jr      z,.named
        ld      hl,(src)
        call    path_base
        ex      de,hl
        ld      hl,(dst)
        call    path_join
        jr      c,.serr
.named: ld      (name),hl
        ex      de,hl                   ; de -> the new name
        ld      hl,(src)
        sys     SYS_RENAME
        ret     nc
        cp      E_XDEV
        jr      nz,.serr
        ld      de,(name)               ; the volume is the new name's
        jp      err_file
.serr:  ld      de,(src)
        jp      err_file

s_usage: db     "mv old new, mv old... dir",0

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/path.inc"
        m6_bss
        bss     dst,2
        bss     src,2
        bss     name,2
        bss     left,2
        bss     todir,1
