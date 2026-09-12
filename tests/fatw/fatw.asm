; fatw — the filesystem's write side: files created, written, extended
; through a hole, appended to, truncated and deleted; the one writer and
; the errors around it; a process writing 64K three ways and reading it
; back; directories made, filled past a cluster, emptied, removed and
; renamed; a volume filled to ENOSPC. Under Nextor: find the driver behind
; the current drive, capture what the resident needs, hand the machine
; over. Then the block above the image does the rest as process 0, through
; the syscalls a program uses, and spawns processes for what only a
; process can show. After every step the cache's headers are read: a dirty
; one is a failure. The report is on screen, the verdict in the mailbox;
; the harness (fatw.tcl) checks the stamp against the host's clock, turns
; the writer's ticks into KB/s and compares the files written with what
; they should hold; tools/run-test.sh then checks every volume of the
; images with the host's FAT checker and compares the two copies of each
; table.
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

banner:     db  "fatw: the filesystem, write",13,10,'$'
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
; segment — the cache headers are at 8000h+ST_HDR here — and it calls the
; kernel the way a program does, through K_SYS.
tblock:
        DISP    K_IMAGE_END

O_CW        equ O_CREAT|O_WRONLY

t_entry:
; --- step 8: create --------------------------------------------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      hl,p_tmp
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_a
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,p_a
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      hl,(t_rec+DE_SIZE)
        ld      a,h
        or      l
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,(t_rec+DE_ATTR)
        and     DA_DIR
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,(t_rec+DE_MTIME)     ; the date word, then the time word
        k_call  API_CON_HEX16
        ld      a,' '
        k_call  API_CON_PUTC
        ld      hl,(t_rec+DE_MTIME+2)
        k_call  API_CON_HEX16
        k_call  API_CON_NEWLINE
        ; The refusals around it.
        ld      hl,p_long83
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0E2h
        call    t_expect
        ld      hl,p_tmp
        ld      a,O_CW
        sys     SYS_OPEN
        ld      b,E_ISDIR
        ld      c,0E4h
        call    t_expect
        ld      hl,p_a
        ld      a,O_WRONLY
        sys     SYS_OPEN
        ld      b,E_BUSY
        ld      c,0E6h
        call    t_expect
        ld      hl,p_a
        xor     a
        sys     SYS_OPEN
        ld      b,E_BUSY
        ld      c,0E8h
        call    t_expect
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_a
        xor     a
        sys     SYS_OPEN
        ld      c,0EAh
        jp      c,t_failc
        sys     SYS_CLOSE
        ld      hl,p_ro
        ld      a,O_WRONLY
        sys     SYS_OPEN
        ld      b,E_ACCES
        ld      c,0EBh
        call    t_expect
        ld      hl,p_ro
        xor     a
        sys     SYS_OPEN
        ld      c,0EDh
        jp      c,t_failc
        sys     SYS_CLOSE
        ld      hl,p_none
        ld      a,O_WRONLY
        sys     SYS_OPEN
        ld      b,E_NOENT
        ld      c,0EEh
        call    t_expect
        ld      hl,p_a
        ld      a,3
        sys     SYS_OPEN
        ld      b,E_INVAL
        ld      c,0F0h
        call    t_expect
        ld      hl,p_a
        ld      a,O_CREAT               ; exists: O_CREAT is ignored
        sys     SYS_OPEN
        ld      c,0F2h
        jp      c,t_failc
        sys     SYS_CLOSE
        call    t_clean
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 9: write ----------------------------------------------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ; "abc", read back.
        ld      hl,p_a
        ld      a,O_WRONLY
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_abc
        ld      bc,3
        sys     SYS_WRITE
        jp      c,t_fail
        ld      de,3
        or      a
        sbc     hl,de
        ld      a,0D1h
        jp      nz,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,s_abc
        ld      c,3
        call    t_readback
        ld      a,0D2h
        jp      nz,t_fail
        ; A byte in the middle, through O_RDWR: read-modify-write.
        ld      hl,p_a
        ld      a,O_RDWR
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,1
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,t_fail
        ld      a,(t_fd)
        ld      hl,s_X
        ld      bc,1
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ld      a,(t_fd)
        ld      hl,t_buf
        ld      bc,16
        sys     SYS_READ
        jp      c,t_fail
        ld      de,3
        or      a
        sbc     hl,de
        ld      a,0D3h
        jp      nz,t_fail
        ld      hl,t_buf
        ld      de,s_aXc
        ld      b,3
        call    t_memeq
        ld      a,0D3h
        jp      nz,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ; Appended: "defg", size 7.
        ld      hl,p_a
        ld      a,O_WRONLY|O_APPEND
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_defg
        ld      bc,4
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_a
        ld      de,7
        call    t_sizeis
        ld      a,0D4h
        jp      nz,t_fail
        ld      hl,s_aXcdefg
        ld      c,7
        call    t_readback
        ld      a,0D5h
        jp      nz,t_fail
        ; A hole: ten bytes at 5000; 7..4999 read as zeros.
        ld      hl,p_a
        ld      a,O_WRONLY
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,5000
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,t_fail
        ld      a,(t_fd)
        ld      hl,s_digits
        ld      bc,10
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_a
        ld      de,5010
        call    t_sizeis
        ld      a,0D6h
        jp      nz,t_fail
        call    t_holecheck
        ld      a,0D7h
        jp      nz,t_fail
        ; Truncated: size 0; nothing to read.
        ld      hl,p_a
        ld      a,O_WRONLY|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        sys     SYS_CLOSE
        ld      hl,p_a
        ld      de,0
        call    t_sizeis
        ld      a,0D8h
        jp      nz,t_fail
        ld      hl,s_abc
        ld      c,0
        call    t_readback
        ld      a,0D9h
        jp      nz,t_fail
        ; write on a read-only descriptor, on a directory, of nothing.
        ld      hl,p_a
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_abc
        ld      bc,3
        sys     SYS_WRITE
        ld      b,E_BADF
        ld      c,0DAh
        call    t_expect
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_tmp
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_abc
        ld      bc,3
        sys     SYS_WRITE
        ld      b,E_ISDIR
        ld      c,0DCh
        call    t_expect
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_a
        ld      a,O_WRONLY
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        ld      a,(t_fd)
        ld      hl,s_abc
        ld      bc,0
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,h
        or      l
        ld      a,0DEh
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        ld      a,0DFh
        jp      nz,t_fail                ; a write of nothing touched the disk
        ld      a,(t_fd)
        sys     SYS_CLOSE
        call    t_clean
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: a process writes 64K three ways ---------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,u_writer
        ld      bc,u_writer_end-u_writer
        ld      a,3
        call    t_run
        or      a
        jp      nz,t_fail_status
        call    t_clean
        ld      hl,t_k10b
        k_call  API_CON_PUTS

; --- step 11: directories --------------------------------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      hl,p_d1
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_d2
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_d3
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_d3
        ld      de,dots_names
        ld      a,2
        call    t_listdir
        jp      c,t_fail
        ld      hl,p_d1
        sys     SYS_MKDIR
        ld      b,E_EXIST
        ld      c,0C0h
        call    t_expect
        ld      hl,p_d1
        sys     SYS_RMDIR
        ld      b,E_NOTEMPTY
        ld      c,0C2h
        call    t_expect
        ld      hl,p_a
        sys     SYS_RMDIR
        ld      b,E_NOTDIR
        ld      c,0C4h
        call    t_expect
        ld      hl,p_root
        sys     SYS_RMDIR
        ld      b,E_BUSY
        ld      c,0C6h
        call    t_expect
        ; A child sits in d3: rmdir is refused until it has gone.
        ld      hl,u_cwd
        ld      bc,u_cwd_end-u_cwd
        ld      a,1
        k_call  API_SPAWN
        jp      c,t_fail
        ld      b,8
.yield: push    bc
        k_call  API_YIELD
        pop     bc
        djnz    .yield
        ld      hl,p_d3
        sys     SYS_RMDIR
        ld      b,E_BUSY
        ld      c,0C8h
        call    t_expect
        k_call  API_WAIT
        jp      c,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status
        ld      hl,p_d3
        sys     SYS_RMDIR
        jp      c,t_fail
        ld      hl,p_d3
        ld      de,t_rec
        sys     SYS_STAT
        ld      b,E_NOENT
        ld      c,0CAh
        call    t_expect
        ; A directory grown past its cluster: 130 files in /tmp/x.
        ld      hl,p_x
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_xfile
        ld      a,130
        call    t_makemany
        jp      c,t_fail
        ld      hl,p_x
        call    t_count
        jp      c,t_fail
        ld      de,132
        or      a
        sbc     hl,de
        ld      a,0CCh
        jp      nz,t_fail
        ld      hl,p_xfile
        ld      a,130
        call    t_unlinkmany
        jp      c,t_fail
        ld      hl,p_x
        sys     SYS_RMDIR
        jp      c,t_fail
        ; A root filled: every entry of /mnt/b's, then all of them removed.
        ld      hl,p_bfile
        ld      a,255
        call    t_makemany
        jr      nc,.notfull
        cp      E_NOSPC
        ld      a,0CDh
        jp      nz,t_fail
        ld      a,(t_n)                 ; how many fitted
        push    af
        ld      hl,t_rootn
        k_call  API_CON_PUTS
        pop     af
        push    af
        call    k_dec8
        k_call  API_CON_NEWLINE
        pop     af
        ld      hl,p_bfile
        call    t_unlinkmany
        jp      c,t_fail
        jr      .rootdone
.notfull:
        ld      a,0CEh                  ; 255 entries fitted a 2M root
        jp      t_fail
.rootdone:
        ; unlink's refusals.
        ld      hl,p_a
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,p_a
        sys     SYS_UNLINK
        ld      b,E_BUSY
        ld      c,0D0h
        call    t_expect
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_tmp
        sys     SYS_UNLINK
        ld      b,E_ISDIR
        ld      c,0D2h
        call    t_expect
        ld      hl,p_ro
        sys     SYS_UNLINK
        ld      b,E_ACCES
        ld      c,0D4h
        call    t_expect
        ld      hl,p_none
        sys     SYS_UNLINK
        ld      b,E_NOENT
        ld      c,0D6h
        call    t_expect
        ; rename: within a directory, to another, a directory moved (its ..
        ; follows), over a file, and every refusal.
        ld      hl,p_a
        ld      a,O_WRONLY
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_hello
        ld      bc,5
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_a
        ld      de,p_b
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_a
        ld      de,t_rec
        sys     SYS_STAT
        ld      b,E_NOENT
        ld      c,0A0h
        call    t_expect
        ld      hl,p_b
        ld      de,p_c
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_c
        ld      de,5
        call    t_sizeis
        ld      a,0A2h
        jp      nz,t_fail
        ld      hl,p_m1
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_m1sub
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_m1sub
        ld      de,p_sub2
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_sub2
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_dotdot
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_rd2                ; d2 is in /tmp/d1: .. reached it
        xor     a
        sys     SYS_OPEN
        ld      c,0A3h
        jp      c,t_failc
        sys     SYS_CLOSE
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,p_m1
        sys     SYS_RMDIR               ; empty again
        jp      c,t_fail
        ; Over a file: e.txt holds "EEE"; c.txt's bytes replace it.
        ld      hl,p_e
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_EEE
        ld      bc,3
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_c
        ld      de,p_e
        sys     SYS_RENAME
        jp      c,t_fail
        ld      hl,p_c
        ld      de,t_rec
        sys     SYS_STAT
        ld      b,E_NOENT
        ld      c,0A4h
        call    t_expect
        ld      hl,p_e
        ld      (t_path),hl
        ld      hl,s_hello
        ld      c,5
        call    t_readback
        ld      a,0A6h
        jp      nz,t_fail
        ld      hl,p_e
        ld      de,p_be
        sys     SYS_RENAME
        ld      b,E_XDEV
        ld      c,0A8h
        call    t_expect
        ld      hl,p_d1
        ld      de,p_d1zz
        sys     SYS_RENAME
        ld      b,E_INVAL
        ld      c,0AAh
        call    t_expect
        ld      hl,p_e
        ld      de,p_d1
        sys     SYS_RENAME
        ld      b,E_EXIST
        ld      c,0ACh
        call    t_expect
        ld      hl,p_d1
        ld      de,p_e
        sys     SYS_RENAME
        ld      b,E_EXIST
        ld      c,0AEh
        call    t_expect
        ld      hl,p_e
        ld      de,p_e
        sys     SYS_RENAME              ; to itself: nothing
        ld      c,0B0h
        jp      c,t_failc
        ld      hl,p_none
        ld      de,p_e
        sys     SYS_RENAME
        ld      b,E_NOENT
        ld      c,0B2h
        call    t_expect
        ld      hl,p_e
        ld      de,p_long83
        sys     SYS_RENAME
        ld      b,E_INVAL
        ld      c,0B4h
        call    t_expect
        ld      hl,p_ro
        ld      de,p_b
        sys     SYS_RENAME
        ld      b,E_ACCES
        ld      c,0B6h
        call    t_expect
        call    t_clean
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 12: a volume filled -------------------------------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        ; A one-cluster file to give back afterwards.
        ld      hl,p_spare
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_abc
        ld      bc,1
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,u_filler
        ld      bc,u_filler_end-u_filler
        ld      a,3
        call    t_run
        or      a
        jp      nz,t_fail_status
        ; Full: a new file's first byte cannot be placed.
        ld      hl,p_again
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,s_abc
        ld      bc,1
        sys     SYS_WRITE
        ld      b,E_NOSPC
        ld      c,0F4h
        call    t_expect
        ; The spare's cluster given back: the byte finds a place.
        ld      hl,p_spare
        sys     SYS_UNLINK
        jp      c,t_fail
        ld      a,(t_fd)
        ld      hl,s_abc
        ld      bc,1
        sys     SYS_WRITE
        jp      c,t_fail
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,p_again
        ld      de,1
        call    t_sizeis
        ld      a,0F6h
        jp      nz,t_fail
        call    t_clean
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
t_sizeis:
        push    de
        ld      de,t_rec
        sys     SYS_STAT
        pop     de
        jp      c,t_fail
        ld      hl,(t_rec+DE_SIZE)
        or      a
        sbc     hl,de
        jr      nz,.no
        ld      hl,(t_rec+DE_SIZE+2)
        ld      a,h
        or      l
        ret     z
.no:    ld      hl,t_size               ; what stat said, for the log
        k_call  API_CON_PUTS
        ld      hl,(t_rec+DE_SIZE)
        k_call  API_CON_DEC16
        or      1
        ret

; t_readback — the file at (t_path), by default /tmp/a.txt: read whole into
; t_buf (up to 512 bytes); Z when C bytes came and they equal HL's.
t_readback:
        push    hl
        push    bc
        ld      hl,(t_path)
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,t_buf
        ld      bc,512
        sys     SYS_READ
        jp      c,t_fail
        push    hl
        ld      a,(t_fd)
        sys     SYS_CLOSE
        pop     hl
        pop     bc
        pop     de                      ; the expected bytes
        ld      a,h
        or      a
        jr      nz,.no
        ld      a,l
        cp      c
        jr      nz,.no
        ld      hl,p_a
        ld      (t_path),hl             ; back to the default
        ld      b,c
        ld      hl,t_buf
        inc     b
        dec     b
        ret     z                       ; nothing to compare: Z
        jp      t_memeq
.no:    ld      hl,p_a
        ld      (t_path),hl
        or      1
        ret

; t_memeq — B bytes at HL and DE: Z if equal.
t_memeq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        djnz    t_memeq
        ret

; t_holecheck — /tmp/a.txt: bytes 7 to 4999 read as zeros, 5000 to 5009 as
; the digits, then the end. Z if so.
t_holecheck:
        ld      hl,p_a
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      hl,7
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ld      hl,7
        ld      (t_off),hl
.chunk: ld      a,(t_fd)
        ld      hl,t_buf
        ld      bc,512
        sys     SYS_READ
        jp      c,t_fail
        ld      a,h
        or      l
        jr      z,.end
        ld      (t_len),hl
        ld      hl,t_buf
        ld      (t_hl),hl
.byte:  ld      hl,(t_off)
        ld      de,5000
        or      a
        sbc     hl,de                   ; the offset past 5000, CF below it
        jr      c,.zero
        ld      de,s_digits
        add     hl,de
        ld      a,(hl)
        jr      .cmp
.zero:  xor     a
.cmp:   ld      hl,(t_hl)
        cp      (hl)
        jr      nz,.bad
        inc     hl
        ld      (t_hl),hl
        ld      hl,(t_off)
        inc     hl
        ld      (t_off),hl
        ld      hl,(t_len)
        dec     hl
        ld      (t_len),hl
        ld      a,h
        or      l
        jr      nz,.byte
        jr      .chunk
.end:   ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      hl,(t_off)
        ld      de,5010
        or      a
        sbc     hl,de
        ret
.bad:   ld      a,(t_fd)
        sys     SYS_CLOSE
        or      1
        ret

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
        ld      b,8
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

t_k8:       db  "8 create mtime ",0
t_k9:       db  "9 write:",0
t_k10:      db  "10 writer",10,0
t_k10b:     db  "10 writer ok",10,0
t_k11:      db  "11 dirs:",0
t_k12:      db  "12 full:",0
t_rootn:    db  "11 root entries ",0
t_ok:       db  " ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_status:   db  " status ",0
t_dirty:    db  " dirty header ",0
t_size:     db  " size ",0

p_tmp:      db  "/tmp",0
p_a:        db  "/tmp/a.txt",0
p_b:        db  "/tmp/b.txt",0
p_c:        db  "/tmp/d1/c.txt",0
p_e:        db  "/tmp/e.txt",0
p_be:       db  "/mnt/b/e.txt",0
p_ro:       db  "/ro.txt",0
p_none:     db  "/tmp/none",0
p_root:     db  "/",0
p_long83:   db  "/tmp/toolongname.txt",0
p_d1:       db  "/tmp/d1",0
p_d2:       db  "/tmp/d1/d2",0
p_d3:       db  "/tmp/d1/d2/d3",0
p_d1zz:     db  "/tmp/d1/d2/zz",0
p_rd2:      db  "d2",0
p_dotdot:   db  "..",0
p_x:        db  "/tmp/x",0
p_xfile:    db  "/tmp/x/x000",0
p_bfile:    db  "/mnt/b/r000",0
p_m1:       db  "/tmp/m1",0
p_m1sub:    db  "/tmp/m1/sub",0
p_sub2:     db  "/tmp/d1/sub2",0
p_spare:    db  "/mnt/b/spare.bin",0
p_again:    db  "/mnt/b/again.txt",0
s_abc:      db  "abc"
s_X:        db  "X"
s_aXc:      db  "aXc"
s_aXcdefg:  db  "aXcdefg"
s_defg:     db  "defg"
s_digits:   db  "0123456789"
s_hello:    db  "hello"
s_EEE:      db  "EEE"
dots_names: db  ".",0,"..",0,0

t_step:     db  0
t_n:        db  0
t_fd:       db  0
t_want:     db  0
t_names:    dw  0
t_pat:      dw  0
t_path:     dw  p_a
t_off:      dw  0
t_hl:       dw  0
t_len:      dw  0
t_calls:    dw  0
t_seen:     ds  8
t_rec:      ds  DIRENT_SIZE
t_buf:      ds  512
        ENT

; The user programs, assembled for P0_PROG and copied there by spawn.
    macro u_image name
name        equ K_IMAGE_END+(name_k-tblock)
name_end    equ name+(name_k_end-name_k)
    endm

; u_writer — three pages. (a) /mnt/d/big.bin on the FAT16 slave: 64K of
; the pattern in four 16K writes from page 1, timed, the driver calls
; counted — 32 data + 2 table + 1 entry per write, plus the table sector's
; first read: 141 — then read back through page 0 and compared. (b)
; /tmp/b4k.bin: the same in 4K writes from page 0, timed. (c)
; /tmp/b1000.bin: the same in 1000-byte writes from an unaligned buffer.
; (d) b4k.bin reopened O_RDWR: 3000 bytes at 30000 inverted, the whole read
; back. Exits with 0, or the number of the check that failed.
U_BUF0      equ 1000h           ; page 0, 256-aligned, 4K
U_BUFU      equ 2001h           ; unaligned, 3000 bytes
U_PAGE1     equ 4000h           ; page 1, 16K
u_writer_k:
        DISP    P0_PROG
        ; (a)
        ld      hl,.big
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ld      hl,(K_BLK_CALLS)
        ld      (.calls),hl
        ld      hl,0
        ld      (.t0),hl                ; the ticks of the calls alone
        ld      de,0                    ; the offset of the chunk
.w16:   push    de
        ld      hl,U_PAGE1
        ld      bc,16384
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x2
        ld      bc,16384
        or      a
        sbc     hl,bc
        jp      nz,.x2
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w16                 ; four chunks: wraps to 0
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
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
        ld      de,141
        or      a
        sbc     hl,de
        jp      nz,.x3
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.big
        call    .readback
        jp      nz,.x4
        ; (b)
        ld      hl,.b4k
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x5
        ld      (.fd),a
        ld      hl,0
        ld      (.t0),hl
        ld      de,0
.w4k:   push    de
        ld      hl,U_BUF0
        ld      bc,4096
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x5
        ld      bc,4096
        or      a
        sbc     hl,bc
        jp      nz,.x5
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w4k
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks4
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.b4k
        call    .readback
        jp      nz,.x6
        ; (c)
        ld      hl,.b1000
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x7
        ld      (.fd),a
        ld      hl,0
        ld      (.t0),hl
        ld      de,0
.w1000: push    de
        ld      hl,65536-536            ; the last piece is 536
        or      a
        sbc     hl,de
        ld      bc,1000
        jr      nz,.piece
        ld      bc,536
.piece: ld      (.len),bc
        ld      hl,U_BUFU
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,(.len)
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x7
        ld      bc,(.len)
        or      a
        sbc     hl,bc
        jp      nz,.x7
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w1000
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks1000
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.b1000
        call    .readback
        jp      nz,.x8
        ; (d)
        ld      hl,.b4k
        ld      a,O_RDWR
        sys     SYS_OPEN
        jp      c,.x9
        ld      (.fd),a
        ld      hl,30000
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      hl,U_BUFU
        ld      de,30000
        ld      bc,3000
        call    .fill
        ld      hl,U_BUFU
        ld      bc,3000
.inv:   ld      a,(hl)
        cpl
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.inv
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,3000
        sys     SYS_WRITE
        jp      c,.x9
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      a,1
        ld      (.inverted),a
        ld      hl,.b4k
        call    .readback
        jp      nz,.x10
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    ld      a,2
        sys     SYS_EXIT
.x3:    ld      a,3
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
; .tick — after a write whose starting ticks are on the stack under the
; return address: .t0 += the ticks it took. Preserves AF (the result) and
; HL.
.tick:  pop     bc                      ; the return address
        pop     de                      ; the ticks before
        push    bc
        push    af
        push    hl
        ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      de,(.t0)
        add     hl,de
        ld      (.t0),hl
        pop     hl
        pop     af
        ret
; .fill — BC bytes at HL with the pattern from offset DE: byte i =
; (i ^ (i >> 8)) & FFh.
.fill:  ld      a,e
        xor     d
        ld      (hl),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.fill
        ret
; .readback — HL = a path: the file read whole in 4K pieces into U_BUF0 and
; compared with the pattern (.inverted: bytes 30000..32999 inverted). Z if
; every byte is right and 65536 came; the first wrong offset in .bad.
.readback:
        xor     a
        sys     SYS_OPEN
        jr      c,.rbad
        ld      (.fd),a
        ld      de,0
.rchunk:
        push    de
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        pop     de
        jr      c,.rbad
        ld      bc,4096
        or      a
        sbc     hl,bc
        jr      nz,.rbad                ; short
        ld      hl,U_BUF0
.rbyte: ld      a,e
        xor     d
        ld      c,a
        ld      a,(.inverted)
        or      a
        jr      z,.plain
        push    hl
        ld      hl,30000
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.flip
        jr      nc,.plain               ; below 30000
        push    hl
        ld      hl,33000
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.plain
        jr      c,.plain                ; at or past 33000
.flip:  ld      a,c
        cpl
        ld      c,a
.plain: ld      a,(hl)
        cp      c
        jr      nz,.rdiff
        inc     hl
        inc     de
        ld      a,l
        or      a
        jr      nz,.rbyte
        ld      a,h
        cp      high (U_BUF0+4096)
        jr      nz,.rbyte
        ld      a,d
        or      e
        jr      nz,.rchunk              ; 16 pieces: wraps to 0
        ld      a,(.fd)
        sys     SYS_CLOSE
        xor     a
        ret
.rdiff: ld      (.bad),de
        m6_puts .s_at
        ld      hl,(.bad)
        call    m6_dec16
        m6_puts .s_nl
.rbad:  ld      a,(.fd)
        sys     SYS_CLOSE
        or      1
        ret
.big:   db      "/mnt/d/big.bin",0
.b4k:   db      "/tmp/b4k.bin",0
.b1000: db      "/tmp/b1000.bin",0
.s_ticks: db    "writer: 64K/16K in ",0
.s_ticks4: db   "writer: 64K/4K in ",0
.s_ticks1000: db "writer: 64K/1000 in ",0
.s_calls: db    "writer: calls ",0
.s_at:  db      "writer: bad byte at ",0
.s_nl:  db      10,0
.fd:    db      0
.t0:    dw      0
.calls: dw      0
.len:   dw      0
.bad:   dw      0
.inverted: db   0
        m6_proglib
        ENT
u_writer_k_end:
        u_image u_writer

; u_cwd — one page: into /tmp/d1/d2/d3, thirty turns, out.
u_cwd_k:
        DISP    P0_PROG
        ld      hl,.path
        sys     SYS_CHDIR
        jr      c,.fail
        ld      b,30
.turn:  push    bc
        sys     SYS_YIELD
        pop     bc
        djnz    .turn
        xor     a
        sys     SYS_EXIT
.fail:  ld      a,90
        sys     SYS_EXIT
.path:  db      "/tmp/d1/d2/d3",0
        ENT
u_cwd_k_end:
        u_image u_cwd

; u_filler — three pages: /mnt/b/fill.bin written 16K at a time from page
; 1 until the volume is full: a short write and then E_NOSPC, or E_NOSPC
; outright. Prints the KB that fitted. Exits 0, or the check that failed.
u_filler_k:
        DISP    P0_PROG
        ld      hl,.path
        ld      a,O_CW
        sys     SYS_OPEN
        jr      c,.x1
        ld      (.fd),a
        ld      hl,0
        ld      (.kb),hl
.w:     ld      a,(.fd)
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        jr      c,.err
        ld      bc,16384
        or      a
        sbc     hl,bc
        jr      nz,.short
        ld      hl,(.kb)
        ld      de,16
        add     hl,de
        ld      (.kb),hl
        jr      .w
.short: ld      a,(.fd)                 ; short: the next one is refused
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        jr      nc,.x3
.err:   cp      E_NOSPC
        jr      nz,.x2
        ld      hl,(.kb)
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
        ld      a,(.fd)
        sys     SYS_CLOSE
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    ld      a,2
        sys     SYS_EXIT
.x3:    ld      a,3
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
.path:  db      "/mnt/b/fill.bin",0
.line:  db      "filler: "
.digits: db     "00000"
        db      " KB and full",10
.linelen equ    $-.line
.fd:    db      0
.kb:    dw      0
        ENT
u_filler_k_end:
        u_image u_filler

tblock_end:
        ASSERT  $ < 8000h
        ; The block lands above the image in page 3, under the wall the
        ; loader read; the emulator's is F1A3h.
        ASSERT  K_IMAGE_END+(tblock_end-tblock) < 0F100h
