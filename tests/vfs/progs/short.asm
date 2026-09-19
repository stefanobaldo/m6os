; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; short — the vfs test's program for the short forms: statl, readdir on
; a descriptor opened with O_SHORT, chdir by locator, getcwd's short
; form, and statfs. Started from the volume with spawnv, one page. Exits
; with 0, or the number of the check that failed, and prints "free N" —
; the boot volume's free clusters as statfs counts them — for the
; harness to check against the image's own table.
        include "kernel/kernel.inc"
        include "m6prog.inc"
LOC     equ DE_NAME+DE_LOC
        m6_header 1
start:
        ; (1) statl /bin/hello: HELLO, on the boot volume, an entry that
        ; has a sector and a cluster.
        ld      hl,p_hello
        ld      de,rec
        sys     SYS_STATL
        jp      c,x1
        ld      hl,rec+DE_NAME
        ld      de,n_hello
        call    streq
        jp      nz,x1
        ld      a,(rec+LOC+DL_VOL)
        ld      hl,K_BLK_ROOT
        cp      (hl)
        jp      nz,x2
        ld      hl,(rec+LOC+DL_SEC)
        ld      a,h
        or      l
        jp      z,x3
        ld      hl,(rec+LOC+DL_CLUS)
        ld      a,h
        or      l
        jp      z,x3
        ; (2) statl /bin: BIN, a directory with a cluster, kept for later.
        ld      hl,p_bin
        ld      de,rec
        sys     SYS_STATL
        jp      c,x4
        ld      hl,rec+DE_NAME
        ld      de,n_bin
        call    streq
        jp      nz,x4
        ld      hl,(rec+LOC+DL_CLUS)
        ld      a,h
        or      l
        jp      z,x5
        ld      (binclus),hl
        ; (3) statl /: cluster 0 and no sector; /mnt: VOL_NONE.
        ld      hl,p_root
        ld      de,rec
        sys     SYS_STATL
        jp      c,x6
        ld      hl,rec+LOC+DL_CLUS
        ld      b,7                     ; the cluster, the sector, the index
        xor     a
.zero:  or      (hl)
        inc     hl
        djnz    .zero
        jp      nz,x6
        ld      hl,p_mnt
        ld      de,rec
        sys     SYS_STATL
        jp      c,x7
        ld      a,(rec+LOC+DL_VOL)
        cp      VOL_NONE
        jp      nz,x7
        ; (4) readdir /bin in the short form: . with the directory's own
        ; cluster at index 0, .. with cluster 0 at index 1, then the four
        ; names in upper case, each once, at indices 2 to 5.
        ld      hl,p_bin
        ld      a,O_RDONLY|O_SHORT
        sys     SYS_OPEN
        jp      c,x8
        ld      (fd),a
        ld      hl,rec
        sys     SYS_READDIR
        jp      c,x8
        ld      hl,rec+DE_NAME
        ld      de,n_dot
        call    streq
        jp      nz,x8
        ld      hl,(rec+LOC+DL_CLUS)
        ld      de,(binclus)
        or      a
        sbc     hl,de
        jp      nz,x9
        ld      a,(rec+LOC+DL_IDX)
        or      a
        jp      nz,x9
        ld      a,(fd)
        ld      hl,rec
        sys     SYS_READDIR
        jp      c,x10
        ld      hl,rec+DE_NAME
        ld      de,n_dotdot
        call    streq
        jp      nz,x10
        ld      hl,(rec+LOC+DL_CLUS)
        ld      a,h
        or      l
        jp      nz,x10
        ld      a,(rec+LOC+DL_IDX)
        cp      1
        jp      nz,x10
        ld      c,2                     ; the index expected next
.names: push    bc
        ld      a,(fd)
        ld      hl,rec
        sys     SYS_READDIR
        pop     bc
        jp      c,x11
        ld      a,h
        or      l
        jr      z,.end
        ld      a,(rec+LOC+DL_IDX)
        cp      c
        jp      nz,x13
        push    bc
        call    seen                    ; the name found in the list, once
        pop     bc
        jp      nz,x12
        inc     c
        jr      .names
.end:   ld      a,c
        cp      6
        jp      nz,x12
        ld      a,(fd)
        sys     SYS_CLOSE
        ; (5) chdir by locator to /bin: hello opens by its bare name and
        ; getcwd's short form says /BIN; the root by locator: /; /mnt:
        ; /mnt; a volume past the table: EINVAL.
        ld      a,(K_BLK_ROOT)
        ld      (loc),a
        ld      hl,(binclus)
        ld      (loc+1),hl
        ld      hl,0
        ld      de,loc
        sys     SYS_CHDIR
        jp      c,x14
        ld      hl,p_rhello
        xor     a
        sys     SYS_OPEN
        jp      c,x14
        sys     SYS_CLOSE
        ld      hl,buf
        ld      bc,PATH_MAX|8000h
        sys     SYS_GETCWD
        jp      c,x15
        ld      hl,buf
        ld      de,n_sbin
        call    streq
        jp      nz,x15
        ld      hl,0
        ld      (loc+1),hl
        ld      hl,0
        ld      de,loc
        sys     SYS_CHDIR
        jp      c,x16
        ld      hl,buf
        ld      bc,PATH_MAX|8000h
        sys     SYS_GETCWD
        jp      c,x16
        ld      hl,buf
        ld      de,n_sroot
        call    streq
        jp      nz,x16
        ld      a,VOL_NONE
        ld      (loc),a
        ld      hl,0
        ld      de,loc
        sys     SYS_CHDIR
        jp      c,x17
        ld      hl,buf
        ld      bc,PATH_MAX|8000h
        sys     SYS_GETCWD
        jp      c,x17
        ld      hl,buf
        ld      de,n_smnt
        call    streq
        jp      nz,x17
        ld      a,VOL_N
        ld      (loc),a
        ld      hl,0
        ld      de,loc
        sys     SYS_CHDIR
        jp      nc,x18
        cp      E_INVAL
        jp      nz,x18
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,x18
        ; (6) statfs of the boot volume: 512-byte sectors, two tables,
        ; no count with B = 0; the count with B = 1, printed for the
        ; harness; ENODEV past the table.
        ld      a,(K_BLK_ROOT)
        ld      hl,sf
        ld      b,0
        sys     SYS_STATFS
        jp      c,x19
        ld      hl,(sf+SF_SECSIZE)
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,x19
        ld      a,(sf+SF_NFATS)
        cp      2
        jp      nz,x19
        ld      hl,(sf+SF_FREE)
        ld      a,h
        or      l
        jp      nz,x19
        ld      a,(K_BLK_ROOT)
        ld      hl,sf
        ld      b,1
        sys     SYS_STATFS
        jp      c,x20
        ld      hl,(sf+SF_FREE)
        ld      a,h
        or      l
        jp      z,x20
        m6_puts s_free
        ld      hl,(sf+SF_FREE)
        call    m6_dec16
        m6_puts s_nl
        ld      a,VOL_N-1
        ld      hl,sf
        ld      b,0
        sys     SYS_STATFS
        jp      nc,x21
        cp      E_NODEV
        jp      nz,x21
        xor     a
exit:   sys     SYS_EXIT
x1:    ld      a,1
        jr      exit
x2:    ld      a,2
        jr      exit
x3:    ld      a,3
        jr      exit
x4:    ld      a,4
        jr      exit
x5:    ld      a,5
        jr      exit
x6:    ld      a,6
        jr      exit
x7:    ld      a,7
        jr      exit
x8:    ld      a,8
        jr      exit
x9:    ld      a,9
        jp      exit
x10:    ld      a,10
        jp      exit
x11:    ld      a,11
        jp      exit
x12:    ld      a,12
        jp      exit
x13:    ld      a,13
        jp      exit
x14:    ld      a,14
        jp      exit
x15:    ld      a,15
        jp      exit
x16:    ld      a,16
        jp      exit
x17:    ld      a,17
        jp      exit
x18:    ld      a,18
        jp      exit
x19:    ld      a,19
        jp      exit
x20:    ld      a,20
        jp      exit
x21:    ld      a,21
        jp      exit

; streq — HL, DE -> 0-terminated strings: Z when equal. Corrupts AF, HL,
; DE.
streq:  ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      streq

; seen — rec's name against the list at names: Z when it is there and
; was not seen before, its mark set. Corrupts everything.
seen:   ld      de,names
        ld      ix,marks
.one:   ld      a,(de)
        or      a
        jr      z,.no
        ld      hl,rec+DE_NAME
        push    de
        call    streq
        pop     de
        jr      z,.hit
.skip:  ld      a,(de)
        inc     de
        or      a
        jr      nz,.skip
        inc     ix
        jr      .one
.hit:   ld      a,(ix+0)
        or      a
        jr      nz,.no                  ; seen before
        ld      (ix+0),1
        ret                             ; Z
.no:    or      1
        ret

        m6_proglib

p_hello:    db  "/bin/hello",0
p_bin:      db  "/bin",0
p_root:     db  "/",0
p_mnt:      db  "/mnt",0
p_rhello:   db  "hello",0
n_hello:    db  "HELLO",0
n_bin:      db  "BIN",0
n_dot:      db  ".",0
n_dotdot:   db  "..",0
n_sbin:     db  "/BIN",0
n_sroot:    db  "/",0
n_smnt:     db  "/mnt",0
names:      db  "HELLO",0,"TWO",0,"THREE",0,"BIG16K",0,0
s_free:     db  "free ",0
s_nl:       db  10,0
marks:      db  0,0,0,0
fd:         db  0
binclus:    dw  0
loc:        ds  LOC_SIZE
sf:         ds  SF_SIZE
buf:        ds  PATH_MAX
rec:        ds  DIRENT_SIZE
