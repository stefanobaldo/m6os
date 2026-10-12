; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
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
        ld      hl,(B_JIFFY)            ; the boot's clock, before anything
        ld      (REC+KR_JIFFY),hl
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
        inc     hl                      ; KD_KIND, not shown
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
        ld      hl,kbimage
        ld      (REC+KR_BOOT_SRC),hl
        ld      hl,kbimage_end-kbimage
        ld      (REC+KR_BOOT_LEN),hl
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
ld_block    equ 0                   ; nothing above the image: the block
ld_block_len equ 0                  ; runs where it lies, in page 0
        include "loader/takeover.asm"

; The second half, in page 0 of the loader's memory, which the kernel
; keeps as process 0's page 0 so the block runs where it lies — and where
; neither the storage gate nor a switch of page 1 can take it away, which
; a block in page 1 could not say. It runs once the kernel has booted and
; listed the volumes, as process 0, whose page 2 is the storage segment: a
; buffer the cache returns at 4000h+offset is at 8000h+offset here. The
; block layer's entries are called under the window and the storage gate,
; which the block enters and leaves around each call; the test's own data
; lives in this block.
tblock:
        include "blk/block.asm"

tblock_end:
        ASSERT  tblock_end < KB_BASE    ; the block, in page 0, below the
                                        ; boot image's place

; Everything above runs, or is read, while a driver call has switched page
; 1 away, so it stays in page 0; the two images below are
; only copied once page 1 is RAM again, and may extend into it.
        ASSERT  $ < 4000h
kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
        ASSERT  ksimage_end < 8000h

        ds      KT_BOOT-$,0
kbimage:
        incbin  "build/kboot.bin"
kbimage_end:
        ASSERT  kbimage_end-kbimage <= KB_MAX
