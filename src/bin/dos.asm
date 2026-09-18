; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; dos path [args...] — runs an MSX-DOS 2 .COM program with the machine to
; itself, and comes back when it ends: this process becomes the program,
; and the shell reaps the program's DOS termination code as the status.
; The arguments, joined by single spaces behind a leading one, are the
; program's command tail — at most 127 bytes. A path with no dot in its
; last component that is not found is tried again with .com appended.
; The shell runs a command whose word ends in .com through this program
; by itself.
;
; What it does: opens the file and takes its size; allocates three
; segments — two for the program's pages 1 and 2, one for the legacy page
; 3 the program runs under — and maps the first two into its own pages 1
; and 2 with segmap; maps the third into page 2 for a moment to fill it
; with the legacy layer (src/leg/leg.asm, embedded below), a copy of the
; kernel's page 3 from the hinge up, and what the layer needs to know —
; the segments, the drive, the file, the tail as typed; writes the tail at
; 0080h as MSX-DOS does; then dosenter, which never returns: the layer
; loads the program over this one and runs it. A failure frees the
; segments and says why.
        include "kernel/kernel.inc"
        include "lib/prog.inc"

        m6_prog 1
main:   xor     a                       ; nothing taken yet
        ld      (seg1),a
        ld      (seg2),a
        ld      (leg),a
        call    arg_next
        jp      c,usage
        ld      (path),hl
        ; The tail: " arg1 arg2 ...", 0-terminated, at most 127 bytes.
        ld      de,tail
        ld      c,0
.args:  call    arg_next
        jr      c,.tailend
        ld      a,' '
        call    .tailc
.copy:  ld      a,(hl)
        or      a
        jr      z,.args
        call    .tailc
        inc     hl
        jr      .copy
.tailc: inc     c
        jp      z,toolong               ; 255 seen: far too long
        ld      b,a
        ld      a,c
        cp      128
        jp      nc,toolong
        ld      a,b
        ld      (de),a
        inc     de
        ret
.tailend:
        xor     a
        ld      (de),a
        ld      a,c
        ld      (taillen),a
        ; The file, as given; then with .com when the name has no dot.
        ld      hl,(path)
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      nc,opened
        cp      E_NOENT
        jp      nz,fail
        ld      hl,(path)
        ld      de,pbuf
        ld      b,0                     ; a dot seen since the last /
.scan:  ld      a,(hl)
        or      a
        jr      z,.scanned
        cp      '/'
        jr      nz,.notslash
        ld      b,0
.notslash:
        cp      '.'
        jr      nz,.notdot
        ld      b,1
.notdot:
        ld      (de),a
        inc     hl
        inc     de
        jr      .scan
.scanned:
        ld      a,b
        or      a
        ld      a,E_NOENT
        jp      nz,fail
        ld      hl,s_com
        call    str_copy
        ld      hl,pbuf
        ld      (path),hl
        xor     a
        sys     SYS_OPEN
        jp      c,fail
opened: ld      (fd),a
        ; Its size: the end, then back to the start.
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,failc
        ld      a,d
        or      e
        jp      nz,toobig
        ld      a,h
        or      l
        jp      z,toobig                ; empty
        ld      (size),hl
        ld      de,LEG_TPA+1
        or      a
        sbc     hl,de
        jp      nc,toobig
        ld      a,(fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,failc
        ; Three segments.
        sys     SYS_SEGALLOC
        jp      c,failc
        ld      a,l
        ld      (seg1),a
        sys     SYS_SEGALLOC
        jp      c,failsegs
        ld      a,l
        ld      (seg2),a
        sys     SYS_SEGALLOC
        jp      c,failsegs
        ld      a,l
        ld      (leg),a
        ; Pages 1 and 2 the program's; the legacy segment in page 2 for
        ; a moment, to fill it.
        ld      a,(seg1)
        ld      b,a
        ld      a,1
        sys     SYS_SEGMAP
        jp      c,failsegs
        ld      a,(leg)
        ld      b,a
        ld      a,2
        sys     SYS_SEGMAP
        jp      c,failsegs
        ; The layer at LEG_BASE, the kernel's page 3 from the hinge up.
        ld      hl,leg_start
        ld      de,LEG_BASE-4000h
        ld      bc,leg_end-leg_start
        ldir
        ld      hl,K_HINGE
        ld      de,K_HINGE-4000h
        ld      bc,0-K_HINGE
        ldir
        ; What the layer needs to know.
        ld      hl,(K_MAP)              ; this process's page 0 and page 1
        ld      a,l
        ld      (LEG_SEGS+0-4000h),a
        ld      a,(seg1)
        ld      (LEG_SEGS+1-4000h),a
        ld      a,(seg2)
        ld      (LEG_SEGS+2-4000h),a
        ld      a,(leg)
        ld      (LEG_SEG3-4000h),a
        call    drive
        ld      (LEG_DRIVE-4000h),a
        xor     a
        ld      (LEG_STARTED-4000h),a
        ld      a,(fd)
        ld      (LEG_FD-4000h),a
        ld      hl,(size)
        ld      (LEG_SIZE-4000h),hl
        ld      hl,tail
        ld      de,LEG_PARAMS-4000h
        ld      a,(taillen)
        ld      c,a
        ld      b,0
        inc     bc                      ; the 0 too
        ldir
        ; The program's page 2, and the tail at 0080h, upper-cased.
        ld      a,(seg2)
        ld      b,a
        ld      a,2
        sys     SYS_SEGMAP
        jp      c,failsegs
        ld      hl,tail
        ld      de,0081h
        ld      a,(taillen)
        ld      (0080h),a
        ld      b,a
        inc     b
.upper: ld      a,(hl)
        cp      'a'
        jr      c,.keep
        cp      'z'+1
        jr      nc,.keep
        sub     20h
.keep:  ld      (de),a
        inc     hl
        inc     de
        djnz    .upper
        ; Into the legacy page 3. Only a refusal comes back.
        ld      a,(leg)
        sys     SYS_DOSENTER
failsegs:
        push    af
        ld      a,(leg)
        or      a
        jr      z,.two
        sys     SYS_SEGFREE
.two:   ld      a,(seg2)
        or      a
        jr      z,.one
        sys     SYS_SEGFREE
.one:   ld      a,(seg1)
        sys     SYS_SEGFREE
        pop     af
failc:  push    af
        ld      a,(fd)
        sys     SYS_CLOSE
        pop     af
fail:   ld      de,(path)
        call    err_file
        ld      a,1
        ret

toobig: ld      de,s_toobig
        call    err_msg
        ld      a,(fd)
        sys     SYS_CLOSE
        ld      a,1
        ret
toolong:
        ld      de,s_toolong
        call    err_msg
        ld      a,2
        ret
usage:  ld      de,s_usage
        jp      err_usage

; drive — A = the drive of the current directory: its letter's index for
; /mnt/x, the boot volume's for anything else.
drive:  ld      hl,pbuf
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jr      c,.root
        ld      hl,pbuf
        ld      de,s_mnt
        ld      b,5
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.root
        inc     hl
        inc     de
        djnz    .cmp
        ld      a,(hl)                  ; the letter
        sub     'a'
        cp      VOL_N
        jr      c,.ok
.root:  ld      a,(K_BLK_ROOT)
.ok:    ret

s_usage:        db "dos path [args...]",0
s_toolong:      db "the arguments do not fit a command tail of 127 bytes",0
s_toobig:       db "the program does not fit the TPA",0
s_com:          db ".com",0
s_mnt:          db "/mnt/",0

; The layer, as the legacy page 3 holds it from LEG_BASE.
leg_start:
        incbin  "build/leg.bin"
leg_end:
        ASSERT  leg_end-leg_start <= LEG_MAX

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     path,2
        bss     fd,1
        bss     size,2
        bss     seg1,1
        bss     seg2,1
        bss     leg,1
        bss     taillen,1
        bss     tail,128
        bss     pbuf,PATH_MAX+4
