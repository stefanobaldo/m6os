; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; lfn — long file names: a directory a PC wrote, listed and opened by the
; names its long-name chains carry and by their short aliases; names
; created here with chains and aliases of their own, removed and renamed
; with their chains; the cases no writer makes on purpose, poked into the
; volume and repaired before the end. Under Nextor: find the driver
; behind the current drive, capture what the resident needs, hand the
; machine over. Then the block above the image does the rest as process
; 0, through the syscalls a program uses. The report is on screen, the
; verdict in the mailbox; tools/run-test.sh wrote /LFN with mtools before
; the boot, and afterwards checks every volume with the host's FAT
; checker and, through check.sh, reads the names written here back with
; mtools.
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
        xor     a
        ld      (leading),a
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

banner:     db  "lfn: long file names",13,10,'$'
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
ld_block    equ 0                   ; nothing above the image: the block
ld_block_len equ 0                  ; runs where it lies, in page 1
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

; The second half, in page 1 of the loader's memory, which the kernel
; keeps as process 0's page 1 so the block runs where it lies. It runs once the kernel has
; booted and mounted the volumes, as process 0, whose page 2 is the storage
; segment — the cache headers are at 8000h+ST_HDR here — and it calls the
; kernel the way a program does, through K_SYS.
tblock:
        ASSERT  tblock >= 4000h         ; in page 1: the loader's boot segment,
                                        ; which the kernel keeps as process 0's

O_CW        equ O_CREAT|O_WRONLY

t_entry:
; --- step 8: the volumes ------------------------------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      a,(K_BLK_NVOL)
        call    k_dec8
        k_call  API_CON_NEWLINE
        ld      a,(K_BLK_NVOL)
        cp      2
        ld      a,0E0h                  ; /mnt/b is where the writes go
        jp      c,t_fail
        call    t_clean

; --- step 9: /lfn as mtools wrote it, by the names the chains carry -------
; Less ORPHAN.TXT, deleted under its chain by patch.tcl, and with
; MyFile Two.txt by its alias MYFILE~1.TXT, its chain's checksum being wrong.
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      hl,p_lfn
        ld      de,names_lfn
        ld      a,12
        call    t_listdir
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean

; --- step 10: a file by its long name, its alias, and neither ----------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,p_alias              ; /lfn/mydocu~1.txt
        ld      a,'d'
        ld      c,0E1h
        call    t_holds
        ld      hl,p_longname           ; /lfn/MyDocument.txt
        ld      a,'d'
        ld      c,0E3h
        call    t_holds
        ld      hl,p_wrongcase          ; /lfn/mydocument.TXT
        ld      a,'d'
        ld      c,0E5h
        call    t_holds
        ld      hl,p_inner              ; /lfn/Long Directory Name/inner file.txt
        ld      a,'x'
        ld      c,0E7h
        call    t_holds
        ld      hl,p_profile            ; /lfn/.profile
        ld      a,'f'
        ld      c,0E9h
        call    t_holds
        ld      hl,p_longest            ; the 254-character name
        ld      a,'g'
        ld      c,0EBh
        call    t_holds
        ld      hl,p_my2alias           ; /lfn/myfile~1.txt: the alias works
        ld      a,'i'
        ld      c,0EDh
        call    t_holds
        ld      hl,p_ldir               ; /lfn/Long Directory Name: a directory
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0EFh
        jp      z,t_fail
        ld      hl,t_rec+DE_NAME
        ld      de,s_ldirname
        call    t_streq
        ld      a,0F0h
        jp      nz,t_fail
        ; What is not there: the right length and the wrong text, the
        ; wrong length, the orphaned chain's name, the broken chain's.
        ld      hl,p_wrongtext          ; /lfn/MyDocument.txz
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F1h
        call    t_expect
        ld      hl,p_wronglen           ; /lfn/MyDocument.tx
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F3h
        call    t_expect
        ld      hl,p_orphan             ; /lfn/Orphan.txt
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F5h
        call    t_expect
        ld      hl,p_my2long            ; /lfn/MyFile Two.txt: its chain is broken
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F7h
        call    t_expect
        ld      hl,p_badchar            ; /lfn/a?b
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F9h
        call    t_expect
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean

; --- step 11: the current directory's long name ---------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      hl,t_buf                ; at /: the simplest answer
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jp      c,t_fail
        k_call  API_CON_DEC16
        ld      a,' '
        k_call  API_CON_PUTC
        ld      hl,t_buf
        k_call  API_CON_PUTS
        ld      a,' '
        k_call  API_CON_PUTC
        ld      hl,p_ldir
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_buf
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jp      c,t_fail
        k_call  API_CON_DEC16
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,(t_buf)
        k_call  API_CON_HEX8
        ld      a,(t_buf+1)
        k_call  API_CON_HEX8
        ld      a,' '
        k_call  API_CON_PUTC
        ld      hl,t_buf
        k_call  API_CON_PUTS
        ld      hl,t_buf
        ld      de,s_ldirpath           ; /LFN as mtools made it, the rest as
        call    t_streq                 ; its chain reads
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean

; --- step 12: names made on /mnt/b --------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
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
        ld      hl,p_mntb
        ld      de,names_b
        ld      a,15
        call    t_listdir
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean

; --- step 13: a directory whose chains cross a sector and a cluster --------
        ld      a,13
        ld      (t_step),a
        ld      hl,t_k13
        k_call  API_CON_PUTS
        ld      hl,p_ldirb              ; /mnt/b/Long Dir
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_ldirb
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_buf
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jp      c,t_fail
        ld      hl,t_buf
        ld      de,p_ldirb
        call    t_streq
        ld      a,0E1h
        jp      nz,t_fail
        ; . and .. and thirteen short names fill the first sector but one
        ; slot: a two-part name starts in it and ends in the next.
        ld      hl,p_fpat
        ld      a,13
        call    t_makemany
        jp      c,t_fail
        ld      hl,p_xsec               ; crossing a sector.txt
        ld      a,'c'
        call    t_make
        ld      hl,p_xsec
        ld      a,'c'
        ld      c,0E3h
        call    t_holds
        ; Sixty-two slots of the cluster's sixty-four taken: the next
        ; two-part name ends in a cluster added.
        ld      hl,p_gpat
        ld      a,44
        call    t_makemany
        jp      c,t_fail
        ld      hl,p_xclus              ; crossing a cluster.txt
        ld      a,'k'
        call    t_make
        ld      hl,p_xclus
        ld      a,'k'
        ld      c,0E5h
        call    t_holds
        ld      hl,p_dot
        call    t_count
        jp      c,t_fail
        ld      de,61                   ; ., .., 13 + 1 + 44 + 1
        or      a
        sbc     hl,de
        ld      a,0E7h
        jp      nz,t_fail
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean

; --- step 14: names removed and renamed with their chains ------------------
        ld      a,14
        ld      (t_step),a
        ld      hl,t_k14
        k_call  API_CON_PUTS
        ld      hl,p_space3             ; unlink: the chain goes with the entry
        sys     SYS_UNLINK
        jp      c,t_fail
        ld      hl,p_space3
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0E1h
        call    t_expect
        ld      hl,p_space4a            ; its alias, SPACE_~4, with it
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0E3h
        call    t_expect
        ld      hl,p_hw                 ; a long name to a short one
        ld      de,p_hwshort
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_hwshort
        ld      a,'w'
        ld      c,0E5h
        call    t_holds
        ld      hl,p_hw
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0E7h
        call    t_expect
        ld      hl,p_hwalias
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0E9h
        call    t_expect
        ld      hl,p_rd                 ; a short one to a long one
        ld      de,p_rdlong
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_rdlong
        ld      a,'r'
        ld      c,0EBh
        call    t_holds
        ld      hl,p_rd
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0EDh
        call    t_expect
        ld      hl,p_mixed              ; the case alone: Mixed.TXT to MIXED.txt
        ld      de,p_mixed2
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_mixedlc
        ld      a,'m'
        ld      c,0EFh
        call    t_holds
        ld      hl,p_xyz                ; into the long-named directory
        ld      de,p_xyzmoved
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_xyzmoved
        ld      a,'x'
        ld      c,0F1h
        call    t_holds
        ld      hl,p_empty              ; a long-named directory made and removed
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_empty
        sys     SYS_RMDIR
        jp      c,t_fail
        ld      hl,p_empty
        xor     a
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0F3h
        call    t_expect
        ld      hl,p_ldirb              ; the directory renamed, its chain too
        ld      de,p_ldirb2
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_ldirb2
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_buf
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jp      c,t_fail
        ld      hl,t_buf
        ld      de,p_ldirb2
        call    t_streq
        ld      a,0F5h
        jp      nz,t_fail
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_mntb
        ld      de,names_b2
        ld      a,14
        call    t_listdir
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        call    t_clean
        jp      t_verdict

; t_make — HL = a path, A = a byte: the file created, the byte and a
; newline written, closed. A failure is the test's.
t_make: ld      (t_hold),a
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      a,(t_hold)
        ld      (t_two),a
        ld      hl,t_two
        ld      bc,2
        ld      a,(t_fd)
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ret

; t_holds — HL = a path, A = the byte its file holds first, C = the check's
; code: the file opened and read; a failure is C (the open or the read
; failed), C+1 (a wrong length or byte).
t_holds:
        ld      (t_hold),a
        ld      a,c
        ld      (t_code),a
        xor     a
        sys     SYS_OPEN
        jp      c,.failed
        ld      (t_fd),a
        ld      hl,t_buf
        ld      bc,16
        sys     SYS_READ
        jp      c,.failed
        ld      a,l
        cp      2
        jr      nz,.wrong
        ld      a,(t_buf)
        ld      hl,t_hold
        cp      (hl)
        jr      nz,.wrong
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,.failed
        ret
.wrong: ld      a,(t_code)
        inc     a
        jp      t_fail
.failed:
        ld      b,a
        ld      a,(t_code)
        ld      c,a
        ld      a,b
        jp      t_failc

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
        ld      hl,t_scode
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
t_halt: ei
        halt
        jr      t_halt

; t_failc — a syscall failed where it had to succeed: the errno, then the
; check's code C.
t_failc:
        push    bc
        k_call  API_CON_HEX8
        ld      a,'/'
        k_call  API_CON_PUTC
        pop     bc
        ld      a,c
        jr      t_fail

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

; t_run — HL = an image, BC = its length, A = its pages: spawn it, wait for
; it, A = its status. A failure of spawn or wait is a failure of the test.
t_run:  k_call  API_SPAWN
        jp      c,t_fail
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        ret

; t_expect — after a syscall: CF must be set with A = B, else fail with
; code C (C+1 when the call succeeded); the errno that came is printed
; before the code. Preserves nothing.
t_expect:
        jr      c,.failed
        inc     c
        ld      a,c
        jp      t_fail
.failed:
        cp      b
        ret     z
        jp      t_failc

; t_clean — the step is over: no cache header may be dirty. Fails with
; code FF and the header's index otherwise.
t_clean:
        ld      ix,8000h+ST_HDR
        ld      b,BUF_N
        ld      c,0
.h:     ld      a,(ix+H_VOL)
        cp      VOL_NONE
        jr      z,.next
        ld      a,(ix+H_FLAGS)
        and     HF_DIRTY
        jr      nz,.dirty
.next:  ld      de,H_SIZE
        add     ix,de
        inc     c
        djnz    .h
        ret
.dirty: ld      hl,t_dirty
        k_call  API_CON_PUTS
        ld      a,c
        call    k_dec8
        ld      a,0FFh
        jp      t_fail

; t_sizeis — HL = a path, DE = a size below 64K: Z when stat says so.
t_listdir:
        ld      (t_want),a
        ld      (t_names),de
        xor     a
        sys     SYS_OPEN
        ret     c
        ld      (t_fd),a
        ld      hl,t_seen
        ld      b,16
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
.twice: ld      hl,t_rec+DE_NAME
        k_call  API_CON_PUTS
        ld      a,0E7h
        scf
        ret

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

; t_count — HL = a directory's path: HL = its live entries, . and ..
; included. CF with the errno.
t_count:
        xor     a
        sys     SYS_OPEN
        ret     c
        ld      (t_fd),a
        ld      hl,0
        ld      (t_off),hl
.e:     ld      a,(t_fd)
        ld      hl,t_rec
        sys     SYS_READDIR
        ret     c
        ld      a,h
        or      l
        jr      z,.done
        ld      hl,(t_off)
        inc     hl
        ld      (t_off),hl
        jr      .e
.done:  ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,(t_off)
        or      a
        ret

; t_setnum — HL -> the three digits at the end of a path pattern
; ("...x000"), A = a number: the digits are A's. Corrupts AF, BC, DE, HL.
t_setnum:
        ld      c,100
        call    .d
        ld      c,10
        call    .d
        add     a,'0'
        ld      (hl),a
        ret
.d:     ld      b,'0'-1
.s:     inc     b
        sub     c
        jr      nc,.s
        add     a,c
        ld      (hl),b
        inc     hl
        ret

; t_makemany — HL = a path pattern ending in three digits, A = how many:
; files 0..A-1 created and closed; t_n counts them. CF with the errno of
; the create that failed.
t_makemany:
        ld      (t_pat),hl
        ld      (t_want),a
        xor     a
        ld      (t_n),a
.m:     ld      a,(t_n)
        ld      hl,t_want
        cp      (hl)
        ret     nc                      ; CF clear: all made
        ld      hl,(t_pat)
        push    hl
        ld      bc,0
        xor     a
        cpir                            ; hl -> past the terminator
        dec     hl
        dec     hl
        dec     hl
        dec     hl                      ; -> the three digits
        ld      a,(t_n)
        call    t_setnum
        pop     hl
        ld      a,O_CW
        sys     SYS_OPEN
        ret     c
        sys     SYS_CLOSE
        ld      hl,t_n
        inc     (hl)
        jr      .m

; t_unlinkmany — HL = the pattern, A = how many: files 0..A-1 removed.
t_unlinkmany:
        ld      (t_pat),hl
        ld      (t_want),a
        xor     a
        ld      (t_n),a
.u:     ld      a,(t_n)
        ld      hl,t_want
        cp      (hl)
        ret     nc
        ld      hl,(t_pat)
        push    hl
        ld      bc,0
        xor     a
        cpir
        dec     hl
        dec     hl
        dec     hl
        dec     hl
        ld      a,(t_n)
        call    t_setnum
        pop     hl
        sys     SYS_UNLINK
        ret     c
        ld      hl,t_n
        inc     (hl)
        jr      .u

        include "m6util.asm"


t_k8:       db  "8 volumes ",0
t_k9:       db  "9 /lfn listed:",0
t_k10:      db  "10 names:",0
t_k11:      db  "11 getcwd:",0
t_k12:      db  "12 made:",0
t_k13:      db  "13 crossing:",0
t_k14:      db  "14 removed, renamed:",0
t_ok:       db  " ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  0
t_hold:     db  0
t_scode:    db  " code ",0
t_status:   db  " status ",0
t_dirty:    db  " dirty header ",0

p_root:     db  "/",0
p_dot:      db  ".",0
p_mntb:     db  "/mnt/b",0
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
p_ldirb:    db  "/mnt/b/Long Dir",0
p_ldirb2:   db  "/mnt/b/Renamed Long Dir",0
p_space3:   db  "/mnt/b/spacer 3.rom",0
p_space4a:  db  "/mnt/b/spacer~4.rom",0
p_hwshort:  db  "/mnt/b/hw.txt",0
p_rdlong:   db  "/mnt/b/Read Me First.md",0
p_mixed2:   db  "/mnt/b/MIXED.txt",0
p_xyzmoved: db  "/mnt/b/Long Dir/x.y.z moved",0
p_empty:    db  "/mnt/b/Empty Long Dir",0
p_fpat:     db  "/mnt/b/Long Dir/f000",0
p_gpat:     db  "/mnt/b/Long Dir/g000",0
p_xsec:     db  "/mnt/b/Long Dir/crossing a sector.txt",0
p_xclus:    db  "/mnt/b/Long Dir/crossing a cluster.txt",0
p_lfn:      db  "/lfn",0
p_alias:    db  "/lfn/mydocu~1.txt",0
p_longname: db  "/lfn/MyDocument.txt",0
p_wrongcase: db "/lfn/mydocument.TXT",0
p_wrongtext: db "/lfn/MyDocument.txz",0
p_wronglen: db  "/lfn/MyDocument.tx",0
p_inner:    db  "/lfn/Long Directory Name/inner file.txt",0
p_profile:  db  "/lfn/.profile",0
p_my2alias: db  "/lfn/myfile~1.txt",0
p_my2long:  db  "/lfn/MyFile Two.txt",0
p_orphan:   db  "/lfn/Orphan.txt",0
p_badchar:  db  "/lfn/a?b",0
p_ldir:     db  "/lfn/Long Directory Name",0
s_ldirpath: db  "/LFN/Long Directory Name",0
s_ldirname: db  "Long Directory Name",0
p_longest:  db  "/lfn/"
s_longest:  db  "long-name-"
            DUP 236
            db  "x"
            EDUP
            db  ".txt",0

; The names of /lfn as their chains carry them, the two planted cases
; included: MYFILE~1.TXT stands by its short name, ORPHAN.TXT is gone.
names_lfn:  db  ".",0,"..",0,"readme.md",0,"README2.MD",0,"MyFile.txt",0
            db  "MyDocument.txt",0,"caf",90h,".txt",0,".profile",0
            db  "exactly13chr!",0,"MYFILE~1.TXT",0,"Long Directory Name",0
            db  "long-name-"
            DUP 236
            db  "x"
            EDUP
            db  ".txt",0,0

; The names made on /mnt/b, as their chains carry them.
names_b:    db  "Hello World.txt",0,"readme.md",0,"Mixed.TXT",0,"x.y.z",0
            db  "spacer 0.rom",0,"spacer 1.rom",0,"spacer 2.rom",0,"spacer 3.rom",0
            db  "spacer 4.rom",0,"spacer 5.rom",0,"spacer 6.rom",0,"spacer 7.rom",0
            db  "spacer 8.rom",0,"spacer 9.rom",0
            DUP 244
            db  "y"
            EDUP
            db  ".txt",0,0

; The same after step 14.
names_b2:   db  "hw.txt",0,"Read Me First.md",0,"MIXED.txt",0
            db  "spacer 0.rom",0,"spacer 1.rom",0,"spacer 2.rom",0,"spacer 4.rom",0
            db  "spacer 5.rom",0,"spacer 6.rom",0,"spacer 7.rom",0,"spacer 8.rom",0
            db  "spacer 9.rom",0,"Renamed Long Dir",0
            DUP 244
            db  "y"
            EDUP
            db  ".txt",0,0

t_two:      db  0,10
t_step:     db  0
t_n:        db  0
t_fd:       db  0
t_want:     db  0
t_names:    dw  0
t_pat:      dw  0
t_off:      dw  0
t_seen:     ds  16
t_rec:      ds  DIRENT_SIZE
t_buf:      ds  PATH_MAX            ; the longest read into it is a path


tblock_end:
        ASSERT  $ < 8000h
