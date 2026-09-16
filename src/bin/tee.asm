; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; tee [-a] file... — descriptor 0 to the output and into each file, made
; or emptied, or added to with -a. Each block read goes to the output at
; once; the files are written from a 4 KB buffer when it fills and at
; the end, whole sectors from a 256-byte boundary going straight to the
; driver, so a file gets sixteen writes per 64 KB and not one per block.
; At most five files, the descriptors 3 to 7.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,opts
        ld      de,s_usage
        call    arg_opts
        ld      a,(opt_flags)
        bit     0,a
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        jr      z,.mode
        ld      a,O_WRONLY|O_CREAT|O_APPEND
.mode:  ld      (mode),a
        xor     a
        ld      (nfiles),a
.open:  call    arg_next
        jr      c,.go
        ld      (name),hl
        ld      a,(nfiles)
        cp      TEE_MAX
        jr      z,.many
        ld      a,(mode)
        sys     SYS_OPEN
        jr      c,.oerr
        ld      hl,nfiles
        ld      e,(hl)
        inc     (hl)
        ld      d,0
        ld      hl,fds
        add     hl,de
        ld      (hl),a
        ld      hl,names
        add     hl,de
        add     hl,de
        ld      de,(name)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        jr      .open
.many:  ld      a,E_MFILE
.oerr:  ld      de,(name)
        call    err_file
        jr      .open
.go:    xor     a
        call    in_open
        ld      hl,fbuf
        ld      (fptr),hl
.loop:  call    in_fill
        jr      c,.rerr
        ld      a,b
        or      c
        jr      z,.end
        push    hl
        push    bc
        ld      a,1
        sys     SYS_WRITE
        pop     bc
        pop     hl
        jr      c,.werr
        call    stash
        jr      .loop
.end:   call    flush
        ld      a,(lib_status)
        ret
.rerr:  ld      de,0
        call    err_file
        jr      .end
.werr:  ld      de,0
        call    err_file
        ld      a,1
        ret

; stash — HL -> bytes, BC = how many (at most 512): into the file
; buffer, written out first when they would not fit.
stash:  push    hl
        push    bc
        ld      hl,(fptr)
        add     hl,bc
        ld      de,fbuf+4096
        or      a
        sbc     hl,de
        jr      c,.fits
        jr      z,.fits
        call    flush
.fits:  pop     bc
        pop     hl
        ld      de,(fptr)
        ldir
        ld      (fptr),de
        ret

; flush — the file buffer to each file, then empty.
flush:  ld      hl,(fptr)
        ld      de,fbuf
        or      a
        sbc     hl,de
        ld      (flen),hl
        ld      a,h
        or      l
        ret     z
        ld      hl,fbuf
        ld      (fptr),hl
        ld      a,(nfiles)
        or      a
        ret     z
        ld      b,a
        ld      hl,fds
.each:  push    bc
        push    hl
        ld      a,(hl)
        ld      hl,fbuf
        ld      bc,(flen)
        call    wall
        pop     hl
        pop     bc
        jr      nc,.next
        push    bc
        push    hl
        ld      de,fds
        or      a
        sbc     hl,de
        add     hl,hl
        ld      de,names
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        call    err_file
        pop     hl
        pop     bc
.next:  inc     hl
        djnz    .each
        ret

; wall — A = a descriptor, HL -> bytes, BC = how many: written whole,
; the kernel's short writes followed up; CF with A = the errno.
wall:   ld      (wfd),a
.more:  push    hl
        push    bc
        ld      a,(wfd)
        sys     SYS_WRITE
        pop     bc
        pop     de
        ret     c
        ex      de,hl                   ; de = written, hl -> the bytes
        add     hl,de
        push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = what the kernel did not take
        pop     hl
        ld      a,b
        or      c
        jr      nz,.more                ; owed an error on the next call
        ret

TEE_MAX  equ    5
opts:    db     "a",0
s_usage: db     "tee [-a] file...",0

        include "lib/in.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     mode,1
        bss     nfiles,1
        bss     name,2
        bss     fptr,2
        bss     flen,2
        bss     wfd,1
        bss     fds,TEE_MAX
        bss     names,TEE_MAX*2
        bss_align
        bss     fbuf,4096
