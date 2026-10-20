; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; vfs — the test block of tests/vfs: the filesystem through the
; syscalls — the mounts, the directories, open, read, seek, exec from
; the volume, the reader's throughput. Run in two forms: inside vfs.com,
; in page 1 after the kernel images, where the loader's record names
; it; and from the kernel ROM, assembled on its own for 0100h of page 0
; (tests/romblock.asm, M6_ROM defined): the volume's root then holds no
; system files, which is the one thing written under M6_ROM. The host
; includes m6test.inc, m6prog.inc and the kernel's exports before it.
t_entry:
; --- step 8: the volumes and the mount table ------------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      a,(K_BLK_NVOL)
        call    k_dec8
        ld      hl,t_root
        k_call  API_CON_PUTS
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        ld      a,0E0h                  ; no volume is the boot one
        jp      z,t_fail
        ld      a,(K_BLK_ROOT)
        call    k_dec8
        k_call  API_CON_NEWLINE
        ; One line per volume from the mount table.
        xor     a
.mnt:   ld      (t_n),a
        ld      hl,K_BLK_NVOL
        cp      (hl)
        jp      nc,.mounted
        ld      hl,t_mnt
        k_call  API_CON_PUTS
        ld      a,(t_n)
        add     a,'a'
        k_call  API_CON_PUTC
        ld      a,(t_n)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      ix,8000h+ST_MNT
        add     ix,de
        ld      hl,t_fat12
        bit     0,(ix+M_FLAGS)
        jr      z,.type
        ld      hl,t_fat16
.type:  k_call  API_CON_PUTS
        ld      hl,t_spc
        k_call  API_CON_PUTS
        ld      a,(ix+M_SPC)
        call    k_dec8
        ld      hl,t_fatat
        k_call  API_CON_PUTS
        ld      l,(ix+M_FAT)
        ld      h,(ix+M_FAT+1)
        k_call  API_CON_DEC16
        ld      hl,t_rootat
        k_call  API_CON_PUTS
        ld      l,(ix+M_ROOT)
        ld      h,(ix+M_ROOT+1)
        k_call  API_CON_DEC16
        ld      hl,t_dataat
        k_call  API_CON_PUTS
        ld      l,(ix+M_DATA)
        ld      h,(ix+M_DATA+1)
        k_call  API_CON_DEC16
        ld      hl,t_clusters
        k_call  API_CON_PUTS
        ld      l,(ix+M_NCLUS)
        ld      h,(ix+M_NCLUS+1)
        k_call  API_CON_DEC16
        k_call  API_CON_NEWLINE
        ld      a,(t_n)
        inc     a
        jp      .mnt
.mounted:

; --- step 9: stat, readdir, and every error -----------------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ; stat /bin/hello: a file; its size on screen for the harness.
        ld      hl,p_hello
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,(t_rec+DE_SIZE)
        k_call  API_CON_DEC16
        ld      hl,t_attr
        k_call  API_CON_PUTS
        ld      a,(t_rec+DE_ATTR)
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        ; stat /bin, /, /mnt: directories; /mnt is named.
        ld      hl,p_bin
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E2h
        jp      z,t_fail
        ld      hl,p_root
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E3h
        jp      z,t_fail
        ld      hl,p_mnt
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E4h
        jp      z,t_fail
        ld      hl,t_rec+DE_NAME
        ld      de,n_mnt
        call    t_streq
        ld      a,0E4h
        jp      nz,t_fail
        ; readdir /: the ten names, each once, nothing else — six
        ; under the ROM, whose volume carries no system files.
        ld      hl,p_root
        ld      de,root_names
    IFDEF M6_ROM
        ld      a,6
    ELSE
        ld      a,10
    ENDIF
        call    t_listdir
        jp      c,t_fail
        ; readdir /mnt: a, b, c, d, every one a directory.
        ld      hl,p_mnt
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      c,0
.letter:
        push    bc
        ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR
        pop     bc
        jp      c,t_fail
        ld      a,h
        or      l
        jr      z,.letters
        ld      a,(t_rec+DE_NAME)
        sub     'a'
        cp      c
        ld      a,0E8h
        jp      nz,t_fail
        ld      a,(t_rec+DE_NAME+1)
        or      a
        ld      a,0E8h
        jp      nz,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E8h
        jp      z,t_fail
        inc     c
        jr      .letter
.letters:
        ld      a,(K_BLK_NVOL)
        cp      c
        ld      a,0E8h
        jp      nz,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ; readdir /bin: . and .. first, then the four programs.
        ld      hl,p_bin
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,t_rec
        sys     SYS_READDIR
        jp      c,t_fail
        ld      hl,t_rec+DE_NAME
        ld      de,n_dot
        call    t_streq
        ld      a,0E9h
        jp      nz,t_fail
        ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR
        jp      c,t_fail
        ld      hl,t_rec+DE_NAME
        ld      de,n_dotdot
        call    t_streq
        ld      a,0E9h
        jp      nz,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_bin
        ld      de,bin_names
        ld      a,6
        call    t_listdir
        jp      c,t_fail
        ; readdir /etc: seventeen entries, so the listing passes the eighth
        ; of a sector — where an entry's offset in it stops fitting a byte —
        ; and on into the sector after.
        ld      hl,p_etc
        ld      de,etc_names
        ld      a,17
        call    t_listdir
        jp      c,t_fail
        ; The errors.
        ld      hl,p_nope
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0EAh
        call    t_expect
        ld      hl,p_hellox
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOTDIR
        ld      c,0EBh
        call    t_expect
        ld      hl,p_bin
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,t_buf
        ld      bc,16
        sys     SYS_READ
        ld      b,E_ISDIR
        ld      c,0ECh
        call    t_expect
        ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR             ; the directory reads as one
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_long
        xor     a
        sys     SYS_OPEN
        ld      b,E_NAMETOOLONG
        ld      c,0EDh
        call    t_expect
        ld      a,(t_fd)                ; closed above
        ld      hl,t_buf
        ld      bc,1
        sys     SYS_READ
        ld      b,E_BADF
        ld      c,0EEh
        call    t_expect
        ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR
        ld      b,E_BADF
        ld      c,0F2h
        call    t_expect
        ld      a,(t_fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ld      b,E_BADF
        ld      c,0F3h
        call    t_expect
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      b,E_BADF
        ld      c,0F5h
        call    t_expect
        ld      hl,p_hello
        ld      a,3                     ; no such access mode
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0EFh
        call    t_expect
        ; Descriptors 3 to 7, then EMFILE; readdir on a file: ENOTDIR.
        ld      b,5
.fill:  push    bc
        ld      hl,p_hello
        xor     a
        sys     SYS_OPEN
        pop     bc
        jp      c,t_fail
        ld      c,a
        ld      a,8
        sub     b
        cp      c                       ; 3, 4, 5, 6, 7 in order
        ld      a,0F0h
        jp      nz,t_fail
        djnz    .fill
        ld      hl,p_hello
        xor     a
        sys     SYS_OPEN
        ld      b,E_MFILE
        ld      c,0F0h
        call    t_expect
        ld      a,3
        ld      hl,t_rec
        sys     SYS_READDIR
        ld      b,E_NOTDIR
        ld      c,0F2h
        call    t_expect
        ld      b,5
        ld      c,3
.close: push    bc
        ld      a,c
        sys     SYS_CLOSE
        pop     bc
        ld      a,0F1h
        jp      c,t_fail
        inc     c
        djnz    .close
        ; stat /data/odd.txt: 1001 bytes.
        ld      hl,p_odd
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      hl,(t_rec+DE_SIZE)
        ld      de,1001
        or      a
        sbc     hl,de
        ld      a,0F4h
        jp      nz,t_fail
        ld      hl,(t_rec+DE_SIZE+2)
        ld      a,h
        or      l
        ld      a,0F4h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: a process reads the big file -----------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,p_reader             ; /reader, a program on the volume
        ld      de,0
        ld      bc,t_fdinh
        xor     a
        sys     SYS_SPAWNV
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status        ; the reader's own step
        ld      hl,t_k10b
        k_call  API_CON_PUTS

; --- step 11: the direct path's runs -------------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      hl,p_runs               ; /runs, a program on the volume
        ld      de,0
        ld      bc,t_fdinh
        xor     a
        sys     SYS_SPAWNV
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 12: the current directory -------------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        ld      hl,p_bin
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_rhello              ; hello, relative
        xor     a
        sys     SYS_OPEN
        ld      b,a
        ld      a,0B2h
        jp      c,t_fail
        ld      a,b
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_rtwo
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      hl,(t_rec+DE_SIZE)
        ld      de,16384
        or      a
        sbc     hl,de
        ld      a,0B3h
        jp      c,t_fail                ; two is bigger than a page
        ld      hl,p_odd
        sys     SYS_CHDIR
        ld      b,E_NOTDIR
        ld      c,0B4h
        call    t_expect
        ld      hl,p_mntb
        sys     SYS_CHDIR
        ld      a,0B5h
        jp      c,t_fail
        ld      hl,p_dotdot
        sys     SYS_CHDIR
        ld      a,0B6h
        jp      c,t_fail
        call    t_first_is_a            ; . is /mnt now
        ld      a,0B7h
        jp      nz,t_fail
        ld      hl,p_nope
        sys     SYS_CHDIR
        ld      b,E_NOENT
        ld      c,0B8h
        call    t_expect
        ld      hl,p_root
        sys     SYS_CHDIR
        ld      a,0B9h
        jp      c,t_fail
        ld      hl,p_motd
        xor     a
        sys     SYS_OPEN
        ld      b,a
        ld      a,0BAh
        jp      c,t_fail
        ld      a,b
        push    af
        ld      hl,t_buf
        ld      bc,16
        sys     SYS_READ
        ld      a,0BEh
        jp      c,t_fail
        ld      a,l
        cp      3
        ld      a,0BFh
        jp      nz,t_fail
        ld      hl,t_buf
        ld      de,n_motd
        call    t_streqn3
        ld      a,0C0h
        jp      nz,t_fail
        pop     af
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_bin
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_dotdot              ; /bin/..: the entry, cluster 0
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_autoexec
        xor     a
        sys     SYS_OPEN
        ld      a,0BBh
        jp      c,t_fail
        sys     SYS_CLOSE
        ld      hl,p_rootdd              ; /..: /
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_autoexec
        xor     a
        sys     SYS_OPEN
        ld      a,0BCh
        jp      c,t_fail
        sys     SYS_CLOSE
        ld      hl,p_mntbdd              ; /mnt/b/..: /mnt
        sys     SYS_CHDIR
        jp      c,t_fail
        call    t_first_is_a
        ld      a,0BDh
        jp      nz,t_fail
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 13: exec ---------------------------------------------------------------
        ld      a,13
        ld      (t_step),a
        ld      hl,t_k13
        k_call  API_CON_PUTS
        ; A spawned child execs hello with three arguments: 7.
        ld      hl,u_exec1
        ld      bc,u_exec1_end-u_exec1
        call    t_run1
        cp      7
        jp      nz,t_fail_status
        ; A one-page vfork child execs the two-page program: the parent
        ; wakes, waits, and hands its status on: 33.
        ld      hl,u_execvfh
        ld      bc,u_execvfh_end-u_execvfh
        call    t_run1
        cp      33
        jp      nz,t_fail_status
        ; A three-page vfork parent's child execs hello: the parent's
        ; stack — where its frame is rebuilt — is in page 2, the page the
        ; window takes, so a wake that leaves the kernel's pages mapped is
        ; caught here; and hello's 210 bytes are one partial sector copied
        ; through the cache, so a copy that went to the mapped page 0
        ; instead of the child's fresh one would land on this parent's
        ; code. It hands hello's status on: 7. (Three pages and one is what
        ; the base machine has room for beside this test's own page.)
        ld      hl,u_execvf
        ld      bc,u_execvf_end-u_execvf
        ld      a,3
        call    t_run
        cp      7
        jp      nz,t_fail_status
        ; Three pages, with three one-page processes holding segments: on
        ; the base machine ENOMEM comes back to the child (112); where the
        ; segments exist, the program runs (3).
        ld      hl,SC_SEGMENTS_FREE
        sys     SYS_SYSCONF
        ld      de,4+3                  ; the holders and the parent, then
        or      a                       ; three for the program
        sbc     hl,de
        ld      a,3
        jr      nc,.expect
        ld      a,112
.expect:
        ld      (t_want),a
        ld      b,3
.hold:  push    bc
        ld      hl,u_hold
        ld      bc,u_hold_end-u_hold
        ld      a,1
        k_call  API_SPAWN
        pop     bc
        jp      c,t_fail
        djnz    .hold
        ld      hl,u_execvf3
        ld      bc,u_execvf3_end-u_execvf3
        call    t_run1
        ld      hl,t_want
        cp      (hl)
        jp      nz,t_fail_status
        ; A buffer that reaches page 3, the kernel's, on a read: refused
        ; with EFAULT, from a child: 0.
        ld      hl,u_badbuf
        ld      bc,u_badbuf_end-u_badbuf
        call    t_run1
        or      a
        jp      nz,t_fail_status
        ; Every refusal, from a child: 0.
        ld      hl,u_execerr
        ld      bc,u_execerr_end-u_execerr
        call    t_run1
        or      a
        jp      nz,t_fail_status
        ; A 16K program, timed: the child prints the ticks before, the
        ; program the ticks on entry; 16.
        ld      hl,u_exectime
        ld      bc,u_exectime_end-u_exectime
        call    t_run1
        cp      16
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 14: the short forms, and a volume's parameters --------------------
        ld      a,14
        ld      (t_step),a
        ld      hl,t_k14
        k_call  API_CON_PUTS
        ld      hl,p_short              ; /short, a program on the volume
        ld      de,0
        ld      bc,t_fdinh
        xor     a
        sys     SYS_SPAWNV
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- verdict --------------------------------------------------------------
t_verdict:
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jr      t_halt

; t_fail — A = error code, (t_step) = the step.
t_fail:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_code
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
t_halt: ei
        halt
        jr      t_halt

; t_fail_status — A = a child's exit status that was not 0.
t_fail_status:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_status
        k_call  API_CON_PUTS
        pop     af
        call    k_dec8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_run1 — HL = a one-page image, BC = its length: spawn it, wait for it,
; A = its status. A failure of spawn or wait is a failure of the test.
; t_run — the same with A = the pages.
t_run1:
        ld      a,1
t_run:  k_call  API_SPAWN
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        ret

; t_expect — after a syscall: CF must be set with A = B, else fail with
; code C (C+1 when the call succeeded). Preserves nothing.
t_expect:
        jr      c,.failed
        inc     c
        ld      a,c
        jp      t_fail
.failed:
        cp      b
        ret     z
        ld      a,c
        jp      t_fail

; t_listdir — HL = a directory's path, DE -> a table of A names (each
; 0-terminated, the table ending in an empty name): open it, read every
; entry, and require each name once and no other name. CF with the code
; on failure (E5 an unknown name, E6 a wrong count, E7 a name twice, or
; the syscall's errno). Corrupts everything.
t_listdir:
        ld      (t_want),a
        ld      (t_names),de
        xor     a
        sys     SYS_OPEN
        ret     c
        ld      (t_fd),a
        ld      hl,t_seen
        ld      b,32
.clear: ld      (hl),0
        inc     hl
        djnz    .clear
        xor     a
        ld      (t_n),a
.entry: ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR
        ret     c
        ld      a,h
        or      l
        jr      z,.end
        ; Which name is it?
        ld      hl,(t_names)
        ld      c,0
.name:  ld      a,(hl)
        or      a
        jr      z,.unknown
        push    hl
        push    bc
        ld      de,t_rec+DE_NAME
        ex      de,hl
        call    t_streq
        pop     bc
        pop     hl
        jr      z,.known
.skip:  ld      a,(hl)
        inc     hl
        or      a
        jr      nz,.skip
        inc     c
        jr      .name
.known: ld      b,0
        ld      hl,t_seen
        add     hl,bc
        ld      a,(hl)
        or      a
        jr      nz,.twice
        inc     (hl)
        ld      hl,t_n
        inc     (hl)
        jr      .entry
.end:   ld      a,(t_fd)
        sys     SYS_CLOSE
        ret     c
        ld      a,(t_n)
        ld      hl,t_want
        cp      (hl)
        ld      a,0E6h
        scf
        ret     nz
        or      a
        ret
.unknown:
        ld      hl,t_rec+DE_NAME
        k_call  API_CON_PUTS
        ld      a,0E5h
        scf
        ret
.twice: ld      hl,t_rec+DE_NAME        ; which name came twice: the two
        k_call  API_CON_PUTS            ;   lists share no name, so it also
        ld      a,0E7h                  ;   says which directory it was
        scf
        ret

; t_first_is_a — open ".", read one entry: Z if its name is "a".
t_first_is_a:
        ld      hl,p_dot
        xor     a
        sys     SYS_OPEN
        ret     c
        ld      (t_fd),a
        ld      hl,t_rec
        sys     SYS_READDIR
        ret     c
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,t_rec+DE_NAME
        ld      de,n_a
        jp      t_streq

; t_streq — the 0-terminated strings at HL and DE: Z if equal.
t_streq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      t_streq

; t_streqn3 — three bytes at HL and DE: Z if equal.
t_streqn3:
        ld      b,3
.b:     ld      a,(de)
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        djnz    .b
        ret

        include "m6util.asm"

t_k8:       db  "8 volumes ",0
t_root:     db  " root ",0
t_mnt:      db  "mnt ",0
t_fat12:    db  " fat12",0
t_fat16:    db  " fat16",0
t_spc:      db  " spc ",0
t_fatat:    db  " fat ",0
t_rootat:   db  " root ",0
t_dataat:   db  " data ",0
t_clusters: db  " clusters ",0
t_k9:       db  "9 stat /bin/hello size ",0
t_attr:     db  " attr ",0
t_k10:      db  "10 reader",10,0
t_k10b:     db  "10 reader ok",10,0
t_k11:      db  "11 runs",0
t_k12:      db  "12 chdir: ",0
t_k13:      db  "13 exec: ",0
t_k14:      db  "14 short",10,0
t_ok:       db  " ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_status:   db  " status ",0

p_hello:    db  "/bin/hello",0
p_bin:      db  "/bin",0
p_root:     db  "/",0
p_mnt:      db  "/mnt",0
p_etc:      db  "/etc",0
p_nope:     db  "/nope",0
p_hellox:   db  "/bin/hello/x",0
p_odd:      db  "/data/odd.txt",0
p_rhello:   db  "hello",0
p_rtwo:     db  "two",0
p_mntb:     db  "/mnt/b",0
p_dotdot:   db  "..",0
p_dot:      db  ".",0
p_motd:     db  "etc/motd",0
    IFDEF M6_ROM
p_autoexec: db  "short",0               ; a root file by its relative name:
    ELSE                                ; the ROM's volume has no autoexec
p_autoexec: db  "autoexec.bat",0
    ENDIF
p_rootdd:   db  "/..",0
p_mntbdd:   db  "/mnt/b/..",0
p_short:    db  "/short",0
p_reader:   db  "/reader",0
p_runs:     db  "/runs",0
t_fdinh:    db  0,1,2
p_long:     db  "/"
            DUP PATH_MAX
            db  "x"
            EDUP
            db  0
n_mnt:      db  "mnt",0
n_dot:      db  ".",0
n_dotdot:   db  "..",0
n_a:        db  "a",0
n_motd:     db  "m6",10
; The names as the importer wrote them: short entries in upper case, no
; case bits, listed as they are.
root_names:
    IFNDEF M6_ROM
            db  "NEXTOR.SYS",0,"COMMAND2.COM",0,"VFS.COM",0,"AUTOEXEC.BAT",0
    ENDIF
            db  "BIN",0,"DATA",0,"ETC",0,"SHORT",0,"READER",0,"RUNS",0,0
bin_names:  db  ".",0,"..",0,"HELLO",0,"TWO",0,"THREE",0,"BIG16K",0,0
etc_names:  db  ".",0,"..",0,"MOTD",0
            db  "PAD01",0,"PAD02",0,"PAD03",0,"PAD04",0,"PAD05",0,"PAD06",0
            db  "PAD07",0,"PAD08",0,"PAD09",0,"PAD10",0,"PAD11",0,"PAD12",0
            db  "PAD13",0,"PAD14",0,0

t_step:     db  0
t_n:        db  0
t_fd:       db  0
t_want:     db  0
t_names:    dw  0
t_seen:     ds  32
; The record lives in the storage segment's test area, in page 2 of
; process 0 (KT_BUF_B), not in this block: page 1's room after the two
; kernel images is what the block has, and it ran out.
t_rec       equ KT_BUF_B            ; DIRENT_SIZE bytes of the 512
t_buf:      ds  16

; The user programs, assembled for P0_PROG and copied there by spawn. They
; live in the block, in page 3 once the loader has copied it, where
; process 0 reads them.
    macro u_image name
name        equ name_k
name_end    equ name+(name_k_end-name_k)
    endm


; u_exec1 — exec /bin/hello with three arguments; the errno, plus 100, if
; it comes back.
u_exec1_k:
        DISP    P0_PROG
        ld      hl,.path
        ld      de,.argv
        sys     SYS_EXEC
        add     a,100
        sys     SYS_EXIT
.path:  db      "/bin/hello",0
.argv:  dw      .path,.a1,.a2,0
.a1:    db      "one",0
.a2:    db      "two",0
        ENT
u_exec1_k_end:
        u_image u_exec1

; u_execvfh — vfork; the child execs /bin/two; the parent wakes with the
; child's pid, waits, and exits with the child's status. Run as a
; one-page process.
u_execvfh_k:
        DISP    P0_PROG
        sys     SYS_VFORK
        jr      c,.fail
        ld      a,h
        or      l
        jr      nz,.parent
        ld      hl,.path
        ld      de,0
        sys     SYS_EXEC
        add     a,100
        sys     SYS_EXIT
.parent:
        sys     SYS_WAIT
        jr      c,.fail
        ld      a,l
        sys     SYS_EXIT
.fail:  ld      a,90
        sys     SYS_EXIT
.path:  db      "/bin/two",0
        ENT
u_execvfh_k_end:
        u_image u_execvfh

; u_badbuf — read into a buffer that ends in page 3, where the kernel is:
; EFAULT, and nothing written. Exits 0, or 1 when the kernel accepted it,
; 2 when the file could not be opened.
u_badbuf_k:
        DISP    P0_PROG
        ld      hl,.path
        xor     a
        sys     SYS_OPEN
        jr      c,.x2
        ld      hl,0BFF0h               ; 16 bytes before the kernel's page
        ld      bc,100
        sys     SYS_READ
        jr      nc,.x1
        cp      E_FAULT
        jr      nz,.x1
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    ld      a,2
        sys     SYS_EXIT
.path:  db      "/data/big.bin",0
        ENT
u_badbuf_k_end:
        u_image u_badbuf

; u_execvf — vfork; the child execs /bin/hello with its three arguments;
; the parent wakes, waits, and exits with the child's status — 7 if the
; parent's own code at 0100h survived the child's load. Run as a
; three-page process, whose stack is in page 2.
u_execvf_k:
        DISP    P0_PROG
        sys     SYS_VFORK
        jr      c,.fail
        ld      a,h
        or      l
        jr      nz,.parent
        ld      hl,.path
        ld      de,.argv
        sys     SYS_EXEC
        add     a,100
        sys     SYS_EXIT
.parent:
        sys     SYS_WAIT
        jr      c,.fail
        ld      a,l
        sys     SYS_EXIT
.fail:  ld      a,90
        sys     SYS_EXIT
.path:  db      "/bin/hello",0
.argv:  dw      .path,.a1,.a2,0
.a1:    db      "one",0
.a2:    db      "two",0
        ENT
u_execvf_k_end:
        u_image u_execvf

; u_execvf3 — the same with /bin/three, which wants three pages.
u_execvf3_k:
        DISP    P0_PROG
        sys     SYS_VFORK
        jr      c,.fail
        ld      a,h
        or      l
        jr      nz,.parent
        ld      hl,.path
        ld      de,0
        sys     SYS_EXEC
        add     a,100
        sys     SYS_EXIT
.parent:
        sys     SYS_WAIT
        jr      c,.fail
        ld      a,l
        sys     SYS_EXIT
.fail:  ld      a,90
        sys     SYS_EXIT
.path:  db      "/bin/three",0
        ENT
u_execvf3_k_end:
        u_image u_execvf3

; u_hold — a process that holds its page: it reads the keyboard, which
; nobody types on, for ever.
u_hold_k:
        DISP    P0_PROG
        xor     a
        ld      hl,.buf
        ld      bc,1
        sys     SYS_READ
        ld      a,99
        sys     SYS_EXIT
.buf:   db      0
        ENT
u_hold_k_end:
        u_image u_hold

; u_execerr — every way exec refuses, each with its errno: 0 when all
; four came back as they should, else 200 + the one that did not.
u_execerr_k:
        DISP    P0_PROG
        ld      hl,.odd
        ld      de,0
        sys     SYS_EXEC
        jr      nc,.e1
        cp      E_NOEXEC
        jr      nz,.e1
        ld      hl,.bin
        ld      de,0
        sys     SYS_EXEC
        jr      nc,.e2
        cp      E_ISDIR
        jr      nz,.e2
        ld      hl,.nope
        ld      de,0
        sys     SYS_EXEC
        jr      nc,.e3
        cp      E_NOENT
        jr      nz,.e3
        ld      hl,.hello
        ld      de,.bigargv
        sys     SYS_EXEC
        jr      nc,.e4
        cp      E_2BIG
        jr      nz,.e4
        xor     a
        sys     SYS_EXIT
.e1:    ld      a,201
        sys     SYS_EXIT
.e2:    ld      a,202
        sys     SYS_EXIT
.e3:    ld      a,203
        sys     SYS_EXIT
.e4:    ld      a,204
        sys     SYS_EXIT
.odd:   db      "/data/odd.txt",0
.bin:   db      "/bin",0
.nope:  db      "/nope",0
.hello: db      "/bin/hello",0
.bigargv: dw    .hello,.big,0
.big:   DUP ARGV_MAX
        db      "x"
        EDUP
        db      0
        ENT
u_execerr_k_end:
        u_image u_execerr

; u_exectime — the ticks now on the screen, then exec /bin/big16k, which
; prints the ticks on its entry and exits with 16.
u_exectime_k:
        DISP    P0_PROG
        ld      hl,(K_TICKS)
        ld      de,.digits+4
        ld      b,5
.dig:   push    bc
        ld      bc,10
        call    .div
        add     a,'0'
        ld      (de),a
        dec     de
        pop     bc
        djnz    .dig
        ld      a,1
        ld      hl,.line
        ld      bc,.linelen
        sys     SYS_WRITE
        ld      hl,.path
        ld      de,0
        sys     SYS_EXEC
        add     a,100
        sys     SYS_EXIT
; .div — HL = HL / BC, A = the remainder (BC < 256).
.div:   push    de
        ld      d,0
        ld      e,16
.bit:   add     hl,hl
        rl      d
        ld      a,d
        sub     c
        jr      c,.no
        ld      d,a
        inc     l
.no:    dec     e
        jr      nz,.bit
        ld      a,d
        pop     de
        ret
.line:  db      "exec: t0 "
.digits: db     "00000",10
.linelen equ    $-.line
.path:  db      "/bin/big16k",0
        ENT
u_exectime_k_end:
        u_image u_exectime
