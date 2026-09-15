; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; cp src dst, cp src... dir — each source copied, in rounds of 4096 bytes
; through a buffer on a 256-byte boundary; a destination that is a
; directory takes the source's last component. Nothing is preserved: the
; copy has the archive bit and the time of now. A source that is a
; directory is EISDIR; with more than one source the destination must be
; a directory.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,(lib_argc)
        ld      de,3
        or      a
        sbc     hl,de
        jr      c,usage                 ; fewer than three words
        inc     hl                      ; hl = the number of sources
        ld      (left),hl
        ld      hl,(lib_argc)
        dec     hl
        add     hl,hl
        ld      de,(lib_argv)
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (dst),de                ; the last word
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
        jr      nz,.dsterr              ; anything but a name to create
.file:  ld      hl,(left)
        dec     hl
        ld      a,h
        or      l
        jr      z,.loop                 ; one source onto a file
        ld      a,E_NOTDIR
.dsterr:
        ld      de,(dst)
        call    err_file
        ld      a,1
        ret
.loop:  call    arg_next
        jr      c,.done
        call    copy
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

; copy — HL -> a source: copied to dst, or into it when it is a directory.
copy:   ld      (src),hl
        call    path_isdir
        jp      c,.serr
        ld      a,E_ISDIR
        jp      z,.serr
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
        ld      hl,(src)
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.serr
        ld      (sfd),a
        ld      hl,(name)
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jr      c,.derr1
        ld      (dfd),a
.round: ld      a,(sfd)
        ld      hl,buf
        ld      bc,4096
        sys     SYS_READ
        jr      c,.rerr
        ld      a,h
        or      l
        jr      z,.close
        ld      b,h
        ld      c,l
        ld      de,buf
.write: push    de
        push    bc
        ld      a,(dfd)
        ex      de,hl
        sys     SYS_WRITE
        pop     bc
        pop     de
        jr      c,.werr
        ex      de,hl                   ; de = written, hl -> the bytes
        add     hl,de
        push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = what the kernel did not take
        pop     de
        ld      a,b
        or      c
        jr      nz,.write               ; owed an error on the next call
        jr      .round
.rerr:  ld      de,(src)
        call    err_file
        jr      .close
.werr:  ld      de,(name)
        call    err_file
.close: ld      a,(dfd)
        sys     SYS_CLOSE
.close1:
        ld      a,(sfd)
        sys     SYS_CLOSE
        ret
.derr1: ld      de,(name)
        call    err_file
        jr      .close1
.serr:  ld      de,(src)
        jp      err_file

s_usage: db     "cp src dst, cp src... dir",0

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/path.inc"
        m6_bss
        bss     dst,2
        bss     src,2
        bss     name,2
        bss     left,2
        bss     todir,1
        bss     sfd,1
        bss     dfd,1
        bss_align
        bss     buf,4096
