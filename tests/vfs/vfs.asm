; vfs — the filesystem's read side: every volume mounted, paths looked up
; through FAT12 directories, stat and readdir, the descriptors and their
; errors, a file read whole, aligned and not, sought through and read
; again by a process of its own, the current directory. Under Nextor:
; find the driver behind the current drive, capture what the resident
; needs, hand the machine over. Then the block above the image does the
; rest as process 0, through the syscalls a program uses, and spawns a
; three-page reader for what only a process can show. The report is on
; screen, the verdict in the mailbox; the harness (vfs.tcl) checks the
; mount lines against the images, the file sizes against the staging
; directory, and that the big file's chain crosses a straddling FAT12
; entry.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "m6prog.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_CURDRV     equ 19h
_TERM       equ 62h

CALSLT      equ B_CALSLT

        org     100h

start:
        ld      sp,KT_LSTACK
        ld      a,DBG_ASCII
        out     (DBG_MODE),a

; --- step 0: SCREEN 0 at 80 columns ------------------------------------
        call    ld_screen80
        ld      de,banner
        call    puts

; --- step 1: a Nextor 2 kernel ----------------------------------------
        ld      a,1
        ld      (step),a
        call    ld_nextor2
        jp      nz,fail

; --- step 2: the driver behind the current drive ----------------------
        ld      a,2
        ld      (step),a
        ld      de,s_drive
        call    puts
        ld      c,_CURDRV
        call    BDOS
        ld      (drive),a
        add     a,'A'
        call    putc
        ld      a,(drive)
        ld      ix,REC+KR_DRV
        ld      hl,KT_SCRATCH
        call    nx_find
        or      a
        jp      nz,fail
        ld      (REC+KR_FIRST),hl
        ld      (REC+KR_FIRST+2),de
        call    newline

; --- step 3: capture, the driver table included -----------------------
        ld      a,3
        ld      (step),a
        ld      de,s_capture
        call    puts
        ld      ix,REC
        call    nx_capture
        ld      hl,(REC+KR_WALL)
        call    puthex16
        ld      de,s_drivers
        call    puts
        ld      a,(REC+KR_NDRV)
        call    putdec
        ld      a,(REC+KR_NDRV)
        or      a
        ld      a,0F6h                  ; no driver in the table
        jp      z,fail
        call    newline

; --- the takeover -----------------------------------------------------
        ld      de,s_takeover
        call    puts
        ld      hl,t_entry
        ld      (REC+KR_TEST),hl
        xor     a
        ld      (REC+KR_MEMCAP),a
        ld      hl,ksimage
        ld      (REC+KR_KSEG_SRC),hl
        ld      hl,ksimage_end-ksimage
        ld      (REC+KR_KSEG_LEN),hl
        call    ld_takeover
        jp      fail                    ; it returns only with A = F3h

; fail — A = error code, (step) = the step that failed.
fail:
        push    af
        call    newline
        ld      de,s_fail
        call    puts
        ld      a,(step)
        call    putdec
        ld      de,s_code
        call    puts
        pop     af
        call    puthex8
        call    newline
        m6_verdict M6_FAIL
        ld      b,1
        ld      c,_TERM
        jp      BDOS

; --- console helpers, through the BDOS, echoed to the debug device -----
puts:   push    de
.echo:  ld      a,(de)
        cp      '$'
        jr      z,.out
        out     (DBG_DATA),a
        inc     de
        jr      .echo
.out:   pop     de
        ld      c,_STROUT
        jp      BDOS

putc:   push    hl
        push    de
        push    bc
        ld      (chbuf),a
        ld      de,chbuf
        call    puts
        pop     bc
        pop     de
        pop     hl
        ret

newline:
        ld      a,13
        call    putc
        ld      a,10
        jp      putc

puthex16:
        ld      a,h
        call    puthex8
        ld      a,l
puthex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,putc
        add     a,'A'-'9'-1
        jr      putc

putdec:
        ld      l,a
        ld      h,0
putdec16:
        xor     a
        ld      (leading),a
        ld      de,10000
        call    .digit
        ld      de,1000
        call    .digit
        ld      de,100
        call    .digit
        ld      de,10
        call    .digit
        ld      a,l
        add     a,'0'
        jp      putc
.digit: ld      a,'0'-1
.sub:   inc     a
        or      a
        sbc     hl,de
        jr      nc,.sub
        add     hl,de
        cp      '0'
        jr      nz,.emit
        push    af
        ld      a,(leading)
        or      a
        jr      nz,.zero
        pop     af
        ret
.zero:  pop     af
.emit:  ld      (leading),a
        jp      putc

banner:     db  "vfs: the filesystem, read",13,10,'$'
s_drive:    db  "2 drive $"
s_capture:  db  "3 wall $"
s_drivers:  db  "h drivers $"
s_takeover: db  "-- taking the machine --",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
chbuf:      db  0,'$'
step:       db  0
drive:      db  0
leading:    db  0
REC:        ds  KREC_SIZE

nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"
        include "nextor/capture.asm"

ld_image    equ kimage
ld_rec      equ REC
ld_block    equ tblock
ld_block_len equ tblock_end-tblock
        include "loader/takeover.asm"

; Everything above runs, or is read, while a driver call or an inter-slot
; call may have switched page 1 away, so it stays in page 0; the two images
; and the block below are only copied once page 1 is RAM again, and may
; extend into it, never into page 2, where the tests' buffers are.
        ASSERT  $ < 4000h
kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
        ASSERT  ksimage_end < 8000h

; The second half, assembled for K_IMAGE_END (build/kernel.exp), where the
; loader copies it, above the image in page 3. It runs once the kernel has
; booted and mounted the volumes, as process 0, whose page 2 is the storage
; segment — the mount table is at 8000h+ST_MNT here — and it calls the
; kernel the way a program does, through K_SYS. Its paths and buffers are
; in page 3, which every process sees.
tblock:
        DISP    K_IMAGE_END

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
        ; readdir /: the seven names, each once, nothing else.
        ld      hl,p_root
        ld      de,root_names
        ld      a,7
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
        ld      hl,u_reader
        ld      bc,u_reader_end-u_reader
        ld      a,3
        k_call  API_SPAWN
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status        ; the reader's own step
        ld      hl,t_k10b
        k_call  API_CON_PUTS

; --- step 11: the current directory -------------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
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

; --- step 12: exec ---------------------------------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        ; A spawned child execs hello with three arguments: 7.
        ld      hl,u_exec1
        ld      bc,u_exec1_end-u_exec1
        call    t_run1
        cp      7
        jp      nz,t_fail_status
        ; A vfork child execs the two-page program: the parent wakes, waits,
        ; and hands its status on: 33. The parent has three pages, so its
        ; stack — where its frame is rebuilt — is in page 2, the page the
        ; window takes: a wake that leaves the kernel's pages mapped is
        ; caught here.
        ld      hl,u_execvf
        ld      bc,u_execvf_end-u_execvf
        ld      a,3
        call    t_run
        cp      33
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
t_k11:      db  "11 chdir: ",0
t_k12:      db  "12 exec: ",0
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
p_autoexec: db  "autoexec.bat",0
p_rootdd:   db  "/..",0
p_mntbdd:   db  "/mnt/b/..",0
p_long:     db  "/"
            DUP 129
            db  "x"
            EDUP
            db  0
n_mnt:      db  "mnt",0
n_dot:      db  ".",0
n_dotdot:   db  "..",0
n_a:        db  "a",0
n_motd:     db  "m6",10
root_names: db  "nextor.sys",0,"command2.com",0,"vfs.com",0,"autoexec.bat",0
            db  "bin",0,"data",0,"etc",0,0
bin_names:  db  ".",0,"..",0,"hello",0,"two",0,"three",0,"big16k",0,0
etc_names:  db  ".",0,"..",0,"motd",0
            db  "pad01",0,"pad02",0,"pad03",0,"pad04",0,"pad05",0,"pad06",0
            db  "pad07",0,"pad08",0,"pad09",0,"pad10",0,"pad11",0,"pad12",0
            db  "pad13",0,"pad14",0,0

t_step:     db  0
t_n:        db  0
t_fd:       db  0
t_want:     db  0
t_names:    dw  0
t_seen:     ds  32
t_rec:      ds  DIRENT_SIZE
t_buf:      ds  16
        ENT

; The user programs, assembled for P0_PROG and copied there by spawn. They
; live in the block, in page 3 once the loader has copied it, where
; process 0 reads them.
    macro u_image name
name        equ K_IMAGE_END+(name_k-tblock)
name_end    equ name+(name_k_end-name_k)
    endm

; u_reader — three pages: /data/big.bin read whole through 4K reads into a
; 256-aligned buffer in page 0 (the direct path; the driver calls counted
; on the second pass, which the harness times), 4K into page 2 (the direct
; path through a page the window takes), 4K into an unaligned buffer (the
; copy path), pieces of 1, 3, 511, 513, 1000 and 3000 bytes (across a
; cluster), then seeks: near the end, to the end, past it, negative, back,
; relative. Every byte against the pattern. Exits with 0, or the number of
; the check that failed.
U_BUF0      equ 1000h           ; page 0, 256-aligned
U_BUF2      equ 8000h           ; page 2
U_BUFU      equ 1001h           ; unaligned
u_reader_k:
        DISP    P0_PROG
        ld      hl,.path
        xor     a
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ; Pass 1: the whole file, 4K at a time, verified.
        call    .whole
        jp      nz,.x2
        ; Pass 2: rewind, and the sixteen reads alone, timed, the driver
        ; calls counted: 128 sectors, 128 calls, the FAT already cached.
        ; Nothing is verified here — pass 1 did — so the ticks are the
        ; reads' and not the compare's.
        call    .rewind
        ld      hl,(K_BLK_CALLS)
        ld      (.calls),hl
        ld      hl,(K_TICKS)
        ld      (.t0),hl
        ld      b,16
.timed: push    bc
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        pop     bc
        jp      c,.x2
        ld      de,4096
        or      a
        sbc     hl,de
        jp      nz,.x2
        djnz    .timed
        ld      hl,(K_TICKS)
        ld      de,(.t0)
        or      a
        sbc     hl,de
        push    hl
        m6_puts .s_ticks
        pop     hl
        call    m6_dec16
        m6_puts .s_ticks2
        ld      hl,(K_BLK_CALLS)
        ld      de,(.calls)
        or      a
        sbc     hl,de
        push    hl
        m6_puts .s_calls
        pop     hl
        push    hl
        call    m6_dec16
        m6_puts .s_nl
        pop     hl
        ld      de,128
        or      a
        sbc     hl,de
        jp      nz,.x4
        ; Pass 3: 4K into page 2.
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUF2
        ld      bc,4096
        sys     SYS_READ
        jp      c,.x5
        ld      hl,U_BUF2
        ld      bc,4096
        ld      de,0
        call    .verify
        jp      nz,.x5
        ; Pass 4: 4K into an unaligned buffer.
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,4096
        sys     SYS_READ
        jp      c,.x6
        ld      hl,U_BUFU
        ld      bc,4096
        ld      de,0
        call    .verify
        jp      nz,.x6
        ; Pass 5: odd pieces, across a cluster.
        call    .rewind
        ld      hl,0
        ld      (.off),hl
        ld      ix,.sizes
.odd:   ld      c,(ix+0)
        ld      b,(ix+1)
        ld      a,b
        or      c
        jr      z,.odddone
        push    bc
        ld      a,(.fd)
        ld      hl,U_BUFU
        sys     SYS_READ
        pop     bc
        jp      c,.x7
        or      a
        sbc     hl,bc
        jp      nz,.x8                  ; a short read
        ld      hl,U_BUFU
        ld      de,(.off)
        call    .verify
        jp      nz,.x7
        ld      c,(ix+0)
        ld      b,(ix+1)
        ld      hl,(.off)
        add     hl,bc
        ld      (.off),hl
        inc     ix
        inc     ix
        jr      .odd
.odddone:
        ; Pass 6: seeks.
        ld      a,(.fd)
        ld      hl,65536-100
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,200
        sys     SYS_READ
        jp      c,.x9
        ld      de,100
        or      a
        sbc     hl,de
        jp      nz,.x9                  ; 100 left, not 200
        ld      hl,U_BUFU
        ld      bc,100
        ld      de,65536-100
        call    .verify
        jp      nz,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x9
        ld      a,h
        or      l
        jp      nz,.x9                  ; the end: 0
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,.x12
        ld      a,h
        or      l
        jp      nz,.x12                 ; 65536 = 0001:0000
        ld      a,e
        dec     a
        or      d
        jp      nz,.x12
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x12
        ld      a,h
        or      l
        jp      nz,.x12
        ld      a,(.fd)
        ld      hl,70000 & 0FFFFh
        ld      de,70000 >> 16
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x9
        ld      a,h
        or      l
        jp      nz,.x9                  ; past the end: 0
        ld      a,(.fd)
        ld      hl,0FFFFh
        ld      de,0FFFFh
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      nc,.x10
        cp      E_INVAL
        jp      nz,.x10
        ld      a,(.fd)
        ld      hl,12345
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x11
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,1000
        sys     SYS_READ
        jp      c,.x11
        ld      hl,U_BUFU
        ld      bc,1000
        ld      de,12345
        call    .verify
        jp      nz,.x11
        ld      a,(.fd)
        ld      hl,-100
        ld      de,-1
        ld      b,SEEK_CUR
        sys     SYS_LSEEK
        jp      c,.x11
        ld      de,13245
        or      a
        sbc     hl,de
        jp      nz,.x11
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x11
        ld      hl,U_BUFU
        ld      bc,100
        ld      de,13245
        call    .verify
        jp      nz,.x11
        ld      a,(.fd)
        sys     SYS_CLOSE
        jp      c,.x13
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    m6_puts .s_at
        ld      hl,(.off)
        call    m6_dec16
        m6_puts .s_got
        ld      hl,(.cnt)
        call    m6_dec16
        m6_puts .s_byte
        ld      hl,(.bad)
        call    m6_dec16
        m6_puts .s_is
        ld      a,(.badb)
        ld      l,a
        ld      h,0
        call    m6_dec16
        m6_puts .s_nl
        ld      a,2
        sys     SYS_EXIT
.x4:    ld      a,4
        sys     SYS_EXIT
.x5:    ld      a,5
        sys     SYS_EXIT
.x6:    ld      a,6
        sys     SYS_EXIT
.x7:    ld      a,7
        sys     SYS_EXIT
.x8:    ld      a,8
        sys     SYS_EXIT
.x9:    ld      a,9
        sys     SYS_EXIT
.x10:   ld      a,10
        sys     SYS_EXIT
.x11:   ld      a,11
        sys     SYS_EXIT
.x12:   ld      a,12
        sys     SYS_EXIT
.x13:   ld      a,13
        sys     SYS_EXIT
; .whole — the file from its position, 4K at a time into U_BUF0, verified:
; Z if every byte was right and 65536 were read.
.whole: ld      hl,0
        ld      (.off),hl
.chunk: ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        jr      c,.wbad
        ld      (.cnt),hl
        ld      de,4096
        or      a
        sbc     hl,de
        jr      nz,.wbad                ; short
        ld      hl,U_BUF0
        ld      bc,4096
        ld      de,(.off)
        call    .verify
        ret     nz
        ld      hl,(.off)
        ld      de,4096
        add     hl,de
        ld      (.off),hl
        jr      nc,.chunk               ; 16 chunks: wraps to 0 at the end
        xor     a
        ret
.wbad:  or      1
        ret
; .rewind — the position to 0.
.rewind:
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ret
; .verify — HL -> BC bytes that came from offset DE of the file: Z if
; every byte is (offset ^ (offset >> 8)) & FFh; else NZ with .bad = the
; offset and .badb = the byte found.
.verify:
        ld      a,e
        xor     d
        cp      (hl)
        jr      z,.same
        ld      (.bad),de
        ld      a,(hl)
        ld      (.badb),a
        or      1
        ret
.same:
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.verify
        ret
.path:  db      "/data/big.bin",0
.s_ticks: db    "reader: 64K in ",0
.s_ticks2: db   " ticks",10,0
.s_calls: db    "reader: calls ",0
.s_nl:  db      10,0
.s_at:  db      "reader: chunk at ",0
.s_got: db      " got ",0
.s_byte: db     " bad byte at ",0
.s_is:  db      " is ",0
.sizes: dw      1,3,511,513,1000,3000,0
.fd:    db      0
.off:   dw      0
.cnt:   dw      0
.bad:   dw      0
.badb:  db      0
.t0:    dw      0
.calls: dw      0
        m6_proglib                      ; last: its labels end the reader's
        ENT
u_reader_k_end:
        u_image u_reader

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

; u_execvf — vfork; the child execs /bin/two; the parent wakes with the
; child's pid, waits, and exits with the child's status.
u_execvf_k:
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
.big:   DUP 300
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

tblock_end:
        ASSERT  $ < 8000h
