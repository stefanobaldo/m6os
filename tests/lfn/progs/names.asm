; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; names — the lfn test's step that makes names on /mnt/b, as a program on
; the volume started with spawnv: a long name and its alias, a short
; lower-case one, a mixed-case one, one with two dots, ten sharing an
; alias's base, the longest the path allows, and what cannot be made.
; Exits with 0, or the number of the check that failed; the test's block
; then lists the directory against what it should hold.
        include "kernel/kernel.inc"
        include "m6prog.inc"
O_CW        equ O_CREAT|O_WRONLY
        m6_header 1
start:
        ld      hl,p_hw                 ; a long name: its chain and alias
        ld      a,'w'
        call    t_make
        ld      hl,p_hw
        ld      a,'w'
        ld      c,0E1h
        call    t_holds
        ld      hl,p_hwalias            ; /mnt/b/hellow~1.txt
        ld      a,'w'
        ld      c,0E3h
        call    t_holds
        ld      hl,p_rd                 ; readme.md: a short entry, lower case
        ld      a,'r'
        call    t_make
        ld      hl,p_mixed              ; Mixed.TXT: a chain keeps the case
        ld      a,'m'
        call    t_make
        ld      hl,p_mixedlc            ; /mnt/b/mixed.txt
        ld      a,'m'
        ld      c,0E5h
        call    t_holds
        ld      hl,p_xyz                ; x.y.z: two dots, alias XY~1.Z
        ld      a,'x'
        call    t_make
        ld      hl,p_xyzalias           ; /mnt/b/xy~1.z
        ld      a,'x'
        ld      c,0E7h
        call    t_holds
        ; Ten names sharing their alias's base, SPACER (the space is
        ; dropped, the digit after it is the seventh character): ~1 to ~9,
        ; then the hash form.
        ld      b,10
        ld      a,'0'
.space: push    bc
        ld      (p_space+14),a
        push    af
        ld      hl,p_space
        ld      a,'s'
        call    t_make
        pop     af
        inc     a
        pop     bc
        djnz    .space
        ld      hl,p_space9             ; /mnt/b/spacer~9.rom
        ld      a,'s'
        ld      c,0E9h
        call    t_holds
        ld      hl,p_longb              ; the longest the path allows
        ld      a,'l'
        call    t_make
        ld      hl,p_longb
        ld      a,'l'
        ld      c,0EBh
        call    t_holds
        ; What cannot be made.
        ld      hl,p_bad1               ; a?b
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0EDh
        call    t_expect
        ld      hl,p_bad2               ; a.
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0EFh
        call    t_expect
        ld      hl,p_bad3               ; ...
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0F1h
        call    t_expect
        ld      hl,p_bad4               ; a byte above 7Eh
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0F3h
        call    t_expect
        ld      hl,p_bad5               ; a space last
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0F5h
        call    t_expect
        xor     a
        sys     SYS_EXIT

; t_make — HL = a path, A = a byte: the file created, the byte and a
; newline written, closed. A failure ends the program with 1.
t_make: ld      (t_hold),a
        ld      a,O_CW
        sys     SYS_OPEN
        jr      c,.fail
        ld      (t_fd),a
        ld      a,(t_hold)
        ld      (t_two),a
        ld      hl,t_two
        ld      bc,2
        ld      a,(t_fd)
        sys     SYS_WRITE
        jr      c,.fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jr      c,.fail
        ret
.fail:  ld      a,1
        sys     SYS_EXIT

; t_holds — HL = a path, A = the byte its file holds first, C = the check's
; code: the file opened and read; a failure is C (the open or the read
; failed), C+1 (a wrong length or byte).
t_holds:
        ld      (t_hold),a
        ld      a,c
        ld      (t_code),a
        xor     a
        sys     SYS_OPEN
        jr      c,.failed
        ld      (t_fd),a
        ld      hl,t_buf
        ld      bc,16
        sys     SYS_READ
        jr      c,.failed
        ld      a,l
        cp      2
        jr      nz,.wrong
        ld      a,(t_buf)
        ld      hl,t_hold
        cp      (hl)
        jr      nz,.wrong
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jr      c,.failed
        ret
.wrong: ld      a,(t_code)
        inc     a
        sys     SYS_EXIT
.failed:
        ld      a,(t_code)
        sys     SYS_EXIT

; t_expect — after a syscall: CF must be set with A = B, else the program
; ends with code C (C+1 when the call succeeded).
t_expect:
        jr      c,.failed
        inc     c
        ld      a,c
        sys     SYS_EXIT
.failed:
        cp      b
        ret     z
        ld      a,c
        sys     SYS_EXIT

p_hw:       db  "/mnt/b/Hello World.txt",0
p_hwalias:  db  "/mnt/b/hellow~1.txt",0
p_rd:       db  "/mnt/b/readme.md",0
p_mixed:    db  "/mnt/b/Mixed.TXT",0
p_mixedlc:  db  "/mnt/b/mixed.txt",0
p_xyz:      db  "/mnt/b/x.y.z",0
p_xyzalias: db  "/mnt/b/xy~1.z",0
p_space:    db  "/mnt/b/spacer 0.rom",0
p_space9:   db  "/mnt/b/spacer~9.rom",0
p_longb:    db  "/mnt/b/"
            DUP 244
            db  "y"
            EDUP
            db  ".txt",0
p_bad1:     db  "/mnt/b/a?b",0
p_bad2:     db  "/mnt/b/a.",0
p_bad3:     db  "/mnt/b/...",0
p_bad4:     db  "/mnt/b/a",80h,0
p_bad5:     db  "/mnt/b/a ",0
t_two:      db  0,10
t_hold:     db  0
t_code:     db  0
t_fd:       db  0
t_buf:      ds  16
