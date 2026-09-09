; blk — the block layer: every driver, device and partition listed at boot,
; a sector read through the volume-relative path with its bounds check,
; the cache hit, missed, evicted and written through, a direct read into
; a fresh segment copied both ways, the RTC read. Under Nextor: find the
; driver behind the current drive, capture what the resident needs — the
; driver table included — create a file to write into and find its sector,
; read the boot sector as a reference, hand the machine over. Then the
; block above the image does the rest, calling the resident and the
; switched part through the jump table, under the window and the storage
; gate it enters itself. The report is on screen, the verdict in the
; mailbox; the harness (blk.tcl) checks the listing against the images
; and the file against the disk from outside.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_CURDRV     equ 19h
_SETDTA     equ 1Ah
_OPEN       equ 43h
_CREATE     equ 44h
_CLOSE      equ 45h
_WRITE      equ 49h
_DELETE     equ 4Dh
_FLUSH      equ 5Fh
_TERM       equ 62h
_RDDRV      equ 73h

CALSLT      equ B_CALSLT
SECNUM      equ 8148h           ; 4 bytes: sector number handed to nx_rw

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
        ld      de,s_slot
        call    puts
        ld      a,(REC+KR_DRV+NXD_SLOT)
        call    puthex8
        ld      de,s_dev
        call    puts
        ld      a,(REC+KR_DRV+NXD_DEV)
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,(REC+KR_DRV+NXD_LUN)
        call    putdec
        ld      de,s_first
        call    puts
        ld      hl,(REC+KR_FIRST+2)
        call    puthex16
        ld      hl,(REC+KR_FIRST)
        call    puthex16
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
        ld      hl,REC+KR_DRVS
        ld      a,(REC+KR_NDRV)
        cp      4
        jr      c,.n
        ld      a,4
.n:     ld      b,a
.drv:   push    bc
        push    hl
        ld      de,s_slot
        call    puts
        pop     hl
        ld      a,(hl)
        inc     hl
        push    hl
        call    puthex8
        ld      de,s_bank
        call    puts
        pop     hl
        ld      a,(hl)
        inc     hl
        push    hl
        call    putdec
        pop     hl
        pop     bc
        djnz    .drv
        call    newline

; --- step 4: the file, and its sector ---------------------------------
        ld      a,4
        ld      (step),a
        ld      de,s_file
        call    puts
        ld      de,fname
        ld      c,_DELETE
        call    BDOS                    ; a previous run's; no error check
        ld      a,5Ah                   ; pattern P1
        call    fill_c
        ld      de,fname
        xor     a                       ; open mode: read and write
        ld      b,0                     ; attributes: none
        ld      c,_CREATE
        call    BDOS
        or      a
        jp      nz,fail
        ld      a,b
        ld      (fh),a
        ld      b,a
        ld      de,KT_BUF_C
        ld      hl,512
        ld      c,_WRITE
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      a,(fh)
        ld      b,a
        ld      c,_CLOSE
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      b,0                     ; current drive
        ld      d,0                     ; flush, keep the buffers
        ld      c,_FLUSH
        call    BDOS
        or      a
        jp      nz,fail_del
        ; The boot sector, drive-relative sector 0, into KT_BUF_B — read
        ; after the write, because Nextor rewrites it on the first write.
        ld      c,_SETDTA
        ld      de,KT_BUF_B
        call    BDOS
        ld      a,(drive)
        ld      b,1
        ld      hl,0
        ld      de,0
        ld      c,_RDDRV
        call    BDOS
        or      a
        jp      nz,fail_del
        ; From it: root = reserved + fats * fatsz; rootsecs = rootent / 16;
        ; data = root + rootsecs. Sector size must be 512.
        ld      hl,(KT_BUF_B+0Bh)
        ld      de,512
        or      a
        sbc     hl,de
        ld      a,0F4h                  ; sector size is not 512
        jp      nz,fail_del
        ld      hl,(KT_BUF_B+0Eh)
        ld      de,(KT_BUF_B+16h)
        ld      a,(KT_BUF_B+10h)
.fats:  add     hl,de
        dec     a
        jr      nz,.fats
        ld      (root),hl
        ld      hl,(KT_BUF_B+11h)
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (rootsecs),hl
        ld      de,(root)
        add     hl,de
        ld      (data),hl
        ; Scan the root directory, one sector at a time, read directly.
        ld      hl,0
.scan:  ld      (n),hl
        ex      de,hl
        ld      hl,(rootsecs)
        or      a
        sbc     hl,de
        ld      a,0F5h                  ; entry not in the root directory
        jp      z,fail_del
        call    sec_first
        ld      hl,(root)
        call    add32
        ld      hl,(n)
        call    add32
        call    read_a
        jp      nz,fail_del
        ld      hl,KT_BUF_A
        ld      b,16
.entry: push    hl
        push    bc
        ld      de,fname11
        ld      b,11
.ch:    ld      a,(de)
        cp      (hl)
        jr      nz,.other
        inc     hl
        inc     de
        djnz    .ch
        pop     bc
        pop     ix                      ; the entry
        ld      l,(ix+1Ah)              ; first cluster
        ld      h,(ix+1Bh)
        ld      (cluster),hl
        jr      .found
.other: pop     bc
        pop     hl
        ld      de,32
        add     hl,de
        djnz    .entry
        ld      hl,(n)
        inc     hl
        jr      .scan
.found: ; target = first + data + (cluster - 2) * sectors per cluster
        call    sec_first
        ld      hl,(data)
        call    add32
        ld      hl,(cluster)
        dec     hl
        dec     hl
        ld      a,(KT_BUF_B+0Dh)
.mul:   push    af
        push    hl
        call    add32
        pop     hl
        pop     af
        dec     a
        jr      nz,.mul
        ld      hl,(SECNUM)
        ld      (REC+KR_TARGET),hl
        ld      hl,(SECNUM+2)
        ld      (REC+KR_TARGET+2),hl
        ld      de,s_at
        call    puts
        ld      hl,(REC+KR_TARGET+2)
        call    puthex16
        ld      hl,(REC+KR_TARGET)
        call    puthex16
        ld      de,s_colon
        call    puts
        call    read_a                  ; SECNUM is still the target
        jp      nz,fail_del
        ld      hl,KT_BUF_C
        ld      de,KT_BUF_A
        call    cmp512
        jp      nz,fail_cmp_del
        ld      de,s_ok
        call    puts
        ; KT_BUF_A keeps the file's sector (P1), KT_BUF_B the boot sector.

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

fail_del:
        push    af
        call    delete
        pop     af
        jr      fail
fail_cmp_del:
        push    hl
        push    bc
        call    delete
        pop     bc
        pop     hl
        jr      fail_cmp
delete: ld      de,fname
        ld      c,_DELETE
        jp      BDOS

; fail_cmp — HL = offset of the first difference, B = expected, C = found.
fail_cmp:
        push    hl
        push    bc
        call    newline
        ld      de,s_fail
        call    puts
        ld      a,(step)
        call    putdec
        ld      de,s_diff
        call    puts
        pop     bc
        pop     hl
        push    bc
        call    puthex16
        ld      a,' '
        call    putc
        pop     bc
        ld      a,b
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,c
        call    puthex8
        call    newline
        m6_verdict M6_FAIL
        ld      b,1
        ld      c,_TERM
        jp      BDOS

; sec_first — SECNUM = first device sector of the drive.
sec_first:
        ld      hl,(REC+KR_FIRST)
        ld      (SECNUM),hl
        ld      hl,(REC+KR_FIRST+2)
        ld      (SECNUM+2),hl
        ret

; add32 — SECNUM += HL, HL zero-extended.
add32:  ld      de,(SECNUM)
        add     hl,de
        ld      (SECNUM),hl
        ret     nc
        ld      hl,(SECNUM+2)
        inc     hl
        ld      (SECNUM+2),hl
        ret

; read_a — one sector, SECNUM, directly into KT_BUF_A. Z if ok, else NZ
; with A = the driver's error code.
read_a: ld      ix,REC+KR_DRV
        or      a
        ld      b,1
        ld      hl,KT_BUF_A
        ld      de,SECNUM
        call    nx_rw
        or      a
        ret

; fill_c — KT_BUF_C byte i = (i and 0FFh) xor A.
fill_c: ld      c,a
        ld      hl,KT_BUF_C
        ld      d,2
.outer: ld      b,0
        ld      e,0
.inner: ld      a,e
        xor     c
        ld      (hl),a
        inc     hl
        inc     e
        djnz    .inner
        dec     d
        jr      nz,.outer
        ret

; cmp512 — compare 512 bytes at HL and DE. Z if equal; otherwise NZ with
; HL = offset of the first difference, B = byte at HL, C = byte at DE.
cmp512:
        push    hl
        ld      bc,512
.loop:  ld      a,(de)
        cp      (hl)
        jr      nz,.diff
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        pop     hl
        ret
.diff:  ld      b,(hl)
        ld      c,a
        pop     de
        or      a
        sbc     hl,de                   ; the offset — 0 when the first byte
        ld      a,b                     ; differs, so Z cannot come from it:
        cp      c                       ; the two bytes differ, hence NZ
        ret

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

banner:     db  "blk: the block layer and the cache",13,10,'$'
s_drive:    db  "2 drive $"
s_slot:     db  " slot $"
s_bank:     db  " bank $"
s_dev:      db  " dev $"
s_first:    db  " first $"
s_capture:  db  "3 wall $"
s_drivers:  db  "h drivers $"
s_file:     db  "4 M6BLK.TST$"
s_at:       db  " at $"
s_colon:    db  ": $"
s_takeover: db  "-- taking the machine --",13,10,'$'
fname:      db  "\\M6BLK.TST",0
fname11:    db  "M6BLK   TST"
s_ok:       db  "ok",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
s_diff:     db  " differ at $"
chbuf:      db  0,'$'
step:       db  0
drive:      db  0
leading:    db  0
fh:         db  0
root:       dw  0
rootsecs:   dw  0
data:       dw  0
cluster:    dw  0
n:          dw  0
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

kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
        ASSERT  ksimage_end < 8000h

; The second half, assembled for K_IMAGE_END (build/kernel.exp), where the
; loader copies it, above the image in page 3. It runs once the kernel has
; booted and listed the volumes, as process 0, whose page 2 is the storage
; segment: a buffer the cache returns at 4000h+offset is at 8000h+offset
; here. The block layer's entries are called under the window and the
; storage gate, which the block enters and leaves around each call; the
; test's own data lives in page 3, where neither hides it.
tblock:
        DISP    K_IMAGE_END

    macro t_enter
        kwin_enter
        k_stgate_enter
    endm
    macro t_leave
        k_stgate_leave
        kwin_leave
    endm

t_entry:
; --- step 8: the table -------------------------------------------------
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
        ; t_rel = target - first: the file's sector relative to /.
        ld      hl,(K_REC+KR_TARGET)
        ld      de,(K_REC+KR_FIRST)
        or      a
        sbc     hl,de
        ld      (t_rel),hl
        ld      hl,(K_REC+KR_TARGET+2)
        ld      de,(K_REC+KR_FIRST+2)
        sbc     hl,de
        ld      (t_rel+2),hl

; --- step 9: blk_rw, and its bounds check -----------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,0
        ld      de,0                    ; sector 0 of /
        call    t_seg_bc                ; b = the storage segment
        ld      c,ST_BUF/512+BUF_SCRATCH
        or      a                       ; read
        k_call  API_BLK_RW
        t_leave
        jp      c,t_fail
        ld      hl,8000h+ST_BUF+BUF_SCRATCH*512
        ld      de,KT_BUF_B
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0E1h                  ; not exactly one driver call
        jp      nz,t_fail
        ; sector = count: EIO before the driver.
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        ld      a,(K_BLK_ROOT)
        call    t_row                   ; ix -> the row
        ld      l,(ix+V_COUNT)
        ld      h,(ix+V_COUNT+1)
        ld      e,(ix+V_COUNT+2)
        ld      d,(ix+V_COUNT+3)
        t_enter
        ld      a,(K_BLK_ROOT)
        call    t_seg_bc
        ld      c,ST_BUF/512+BUF_SCRATCH
        or      a
        k_call  API_BLK_RW
        t_leave
        ld      b,a
        ld      a,0E2h                  ; a sector at count was accepted
        jp      nc,t_fail
        ld      a,b
        cp      E_IO
        ld      a,0E3h                  ; refused with the wrong errno
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        ld      a,h
        or      l
        ld      a,0E4h                  ; the driver was called anyway
        jp      nz,t_fail
        ld      a,(K_BLK_LASTERR)
        or      a
        ld      a,0E5h                  ; a refused call left a code
        jp      nz,t_fail
        ; volume = nvol: EINVAL.
        t_enter
        ld      a,(K_BLK_NVOL)
        ld      hl,0
        ld      de,0
        call    t_seg_bc
        ld      c,ST_BUF/512+BUF_SCRATCH
        or      a
        k_call  API_BLK_RW
        t_leave
        ld      b,a
        ld      a,0E6h                  ; a volume past the table was accepted
        jp      nc,t_fail
        ld      a,b
        cp      E_INVAL
        ld      a,0E7h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: the cache -----------------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        call    t_bget_target           ; a miss
        jp      c,t_fail
        ld      (t_buf),hl
        call    t_bget_target           ; a hit: the same buffer, no call
        jp      c,t_fail
        ld      de,(t_buf)
        or      a
        sbc     hl,de
        ld      a,0E8h                  ; a hit returned another buffer
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0E9h                  ; two bgets, not one driver call
        jp      nz,t_fail
        ld      hl,(t_buf)
        call    t_page2                 ; 4000h+offset -> 8000h+offset
        ld      de,KT_BUF_A             ; the file's sector, P1
        call    k_cmp512
        jp      nz,t_fail_cmp
        ; A direct write of P3 from buffer 22 (slot 30) — the path 3.3 will
        ; write data sectors through — while the cache holds the sector: the
        ; next bget must miss and return P3, not the copy it had.
        ld      a,03Ch                  ; pattern P3
        call    k_fill_c
        ld      hl,KT_BUF_C
        ld      de,8000h+ST_BUF+22*512
        ld      bc,512
        ldir
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        call    t_seg_bc
        ld      c,ST_BUF/512+22         ; slot 30
        k_call  API_BWRITE_DIRECT
        t_leave
        jp      c,t_fail
        call    t_bget_target           ; dropped by the write: a miss
        jp      c,t_fail
        call    t_page2
        ld      de,KT_BUF_C             ; P3, from the disk
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        dec     hl
        ld      a,h
        or      l
        ld      a,0EEh                  ; direct write + reread, not two calls
        jp      nz,t_fail
        ; 25 distinct sectors: the table fills and the target leaves it;
        ; then sector 0 again, which the 25th evicted.
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        ld      hl,0
.fill:  ld      (t_n),hl
        push    hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      de,0
        k_call  API_BGET
        t_leave
        pop     hl
        jp      c,t_fail
        inc     hl
        ld      a,l
        cp      25
        jr      c,.fill
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        ld      de,25
        or      a
        sbc     hl,de
        ld      a,h
        or      l
        ld      a,0EAh                  ; 25 distinct sectors, not 25 calls
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,0
        ld      de,0
        k_call  API_BGET
        t_leave
        jp      c,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0EBh                  ; sector 0 was not evicted
        jp      nz,t_fail
        ; Write through: P2 into the target's buffer, bwrite, drop, get.
        ld      a,0A5h
        call    k_fill_c
        call    t_bget_target
        jp      c,t_fail
        ld      (t_buf),hl
        call    t_page2
        ex      de,hl
        ld      hl,KT_BUF_C
        ld      bc,512
        ldir
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      hl,(t_buf)
        k_call  API_BWRITE
        t_leave
        jp      c,t_fail
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        k_call  API_BDROP
        t_leave
        call    t_bget_target           ; from the disk again
        jp      c,t_fail
        call    t_page2
        ld      de,KT_BUF_C
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        dec     hl
        ld      a,h
        or      l
        ld      a,0ECh                  ; write + reread, not two calls
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 11: a direct read into a fresh segment, copied both ways -----
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ; The highest free segment: take every one, give them back, take
        ; the first the allocator hands out — the last it pushed.
.take:  ld      b,1                     ; owner 1: the test
        k_call  API_MEM_ALLOC
        jr      nc,.take
        ld      b,1
        k_call  API_MEM_FREE_ALL
        ld      b,1
        k_call  API_MEM_ALLOC
        jp      c,t_fail
        ld      (t_seg),a
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        k_call  API_MEM_INFO            ; de = usable segments
        ld      hl,128
        or      a
        sbc     hl,de                   ; 128 - usable
        jr      nc,.small               ; usable <= 128
        ld      a,(t_seg)
        cp      128
        ld      a,0EDh                  ; a large machine gave a low segment
        jp      c,t_fail
.small: t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        ld      a,(t_seg)
        ld      b,a
        ld      c,3                     ; slot 3: offset 0600h
        ld      a,(K_BLK_ROOT)
        k_call  API_BREAD_DIRECT
        t_leave
        jp      c,t_fail
        ; From (seg, 0600h) into the storage segment's scratch buffer.
        t_enter
        ld      a,(t_seg)
        ld      ixh,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixl,a
        ld      hl,0600h
        ld      de,ST_BUF+BUF_SCRATCH*512
        ld      bc,512
        k_call  API_K_COPY
        t_leave
        ld      hl,8000h+ST_BUF+BUF_SCRATCH*512
        ld      de,KT_BUF_C             ; P2, what the file holds now
        call    k_cmp512
        jp      nz,t_fail_cmp
        ; And back: from the scratch buffer into (seg, 0A00h), then from
        ; there into buffer 22, and compare.
        t_enter
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixh,a
        ld      a,(t_seg)
        ld      ixl,a
        ld      hl,ST_BUF+BUF_SCRATCH*512
        ld      de,0A00h
        ld      bc,512
        k_call  API_K_COPY
        ld      a,(t_seg)
        ld      ixh,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixl,a
        ld      hl,0A00h
        ld      de,ST_BUF+22*512
        ld      bc,512
        k_call  API_K_COPY
        t_leave
        ld      hl,8000h+ST_BUF+22*512
        ld      de,KT_BUF_C
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      a,(t_seg)
        ld      b,1
        k_call  API_MEM_FREE
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 12: the RTC --------------------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        t_enter
        k_call  API_RTC_READ
        t_leave
        ld      (t_date),hl
        ld      (t_time),de
        ; YYYY-MM-DD HH:MM:SS from the two words.
        ld      hl,(t_date)
        ld      a,h
        srl     a                       ; year - 1980
        ld      l,a
        ld      h,0
        ld      de,1980
        add     hl,de
        k_call  API_CON_DEC16
        ld      a,'-'
        k_call  API_CON_PUTC
        ld      hl,(t_date)
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; month into bits 8-11 of h
        ld      a,h
        and     0Fh
        call    t_dec2
        ld      a,'-'
        k_call  API_CON_PUTC
        ld      a,(t_date)
        and     1Fh
        call    t_dec2
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,(t_time+1)
        srl     a
        srl     a
        srl     a                       ; hour
        call    t_dec2
        ld      a,':'
        k_call  API_CON_PUTC
        ld      hl,(t_time)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,h
        and     3Fh                     ; minute
        call    t_dec2
        ld      a,':'
        k_call  API_CON_PUTC
        ld      a,(t_time)
        and     1Fh
        add     a,a                     ; second
        call    t_dec2
        k_call  API_CON_NEWLINE

; --- step 13: verdict -------------------------------------------------
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

; t_fail_cmp — HL = offset of the first difference, B = expected, C = found.
t_fail_cmp:
        push    hl
        push    bc
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_diff
        k_call  API_CON_PUTS
        pop     bc
        pop     hl
        push    bc
        k_call  API_CON_HEX16
        ld      a,' '
        k_call  API_CON_PUTC
        pop     bc
        ld      a,b
        k_call  API_CON_HEX8
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,c
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_bget_target — bget of the file's sector on /, under the gate. Out: HL
; = the buffer (page 1 address), or CF.
t_bget_target:
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        k_call  API_BGET
        t_leave
        ret

; t_page2 — HL, a page-1 address of the storage segment as the cache
; returns it, to the same byte as process 0 sees it in page 2.
t_page2:
        ld      a,h
        add     a,40h
        ld      h,a
        ret

; t_seg_bc — B = the storage segment. Preserves everything else.
t_seg_bc:
        push    af
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        pop     af
        ret

; t_row — A = a volume: IX -> its row.
t_row:  ld      ix,K_VOL
        or      a
        ret     z
        ld      de,VOL_SIZE
.mul:   add     ix,de
        dec     a
        jr      nz,.mul
        ret

; t_dec2 — A as two decimal digits.
t_dec2: ld      c,'0'
.tens:  cp      10
        jr      c,.units
        sub     10
        inc     c
        jr      .tens
.units: push    af
        ld      a,c
        k_call  API_CON_PUTC
        pop     af
        add     a,'0'
        k_call  API_CON_PUTC
        ret

        include "m6util.asm"

t_k8:       db  "8 volumes ",0
t_root:     db  " root ",0
t_k9:       db  "9 blk_rw, bounds: ",0
t_k10:      db  "10 cache hit, evict, write through: ",0
t_k11:      db  "11 direct read into segment ",0
t_k12:      db  "12 rtc ",0
t_ok:       db  " ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_diff:     db  " differ at ",0

t_step:     db  0
t_seg:      db  0
t_n:        dw  0
t_calls:    dw  0
t_buf:      dw  0
t_rel:      ds  4
t_date:     dw  0
t_time:     dw  0
        ENT
tblock_end:

        ASSERT $ < 4000h
