; drvcall — find the Nextor driver behind the current drive and call its
; DEV_RW directly, bypassing the Nextor kernel: read a sector both ways
; and compare, write a sector directly and read it back through Nextor,
; then read repeatedly with interrupts enabled. Runs under Nextor, in
; openMSX and on real hardware alike; prints a report, leaves the verdict
; in the mailbox and returns to the command interpreter.
        include "m6test.inc"
        include "nextor/nextor.inc"

; MSX-DOS 2 function calls used here (DOS2-FCS.TXT, Nextor Programmers
; Reference). Strings for _STROUT end in '$'.
_STROUT     equ 09h
_CURDRV     equ 19h
_SETDTA     equ 1Ah
_OPEN       equ 43h
_CREATE     equ 44h
_CLOSE      equ 45h
_READ       equ 48h
_WRITE      equ 49h
_DELETE     equ 4Dh
_FLUSH      equ 5Fh
_TERM       equ 62h
_DOSVER     equ 6Fh
_RDDRV      equ 73h

; Buffers, all above page 1 as DEV_RW requires (page 1 is switched away
; during a direct call). MAILBOX is 8000h-8003h.
SCRATCH     equ 8100h           ; 64 bytes: _GDLI / _GDRVR blocks
DESC        equ 8140h           ; NXD_SIZE bytes: the driver descriptor
FIRST       equ 8144h           ; 4 bytes: first device sector of the drive
SECNUM      equ 8148h           ; 4 bytes: sector number handed to nx_rw
BUF_A       equ 8200h           ; 512: read through Nextor
BUF_B       equ 8400h           ; 512: read through the driver directly
BUF_C       equ 8600h           ; 512: patterns and file data
TARGET      equ 814Ch           ; 4 bytes: device sector of the test file
JIFFY       equ 0FC9Eh          ; BIOS: 16-bit tick counter, 50/60 Hz

        org     100h

start:
        ld      de,banner
        call    puts

; --- step 1: a Nextor 2 kernel ----------------------------------------
        ld      a,1
        ld      (step),a
        ld      de,s_version
        call    puts
        ld      c,_DOSVER
        ld      b,5Ah
        ld      hl,1234h
        ld      de,0ABCDh
        ld      ix,0
        call    BDOS
        or      a
        jp      nz,fail
        ld      a,b
        cp      2
        ld      a,0F0h                  ; not MSX-DOS 2 or later
        jp      c,fail
        ld      a,ixh
        cp      1
        ld      a,0F1h                  ; MSX-DOS 2, not Nextor
        jp      nz,fail
        ld      a,ixl
        cp      2
        ld      a,0F2h                  ; Nextor, but not a 2.x kernel
        jp      nz,fail
        ld      a,ixl
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,iyh
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,iyl
        call    putdec
        call    newline

; --- step 2: every driver in the system -------------------------------
        ld      a,2
        ld      (step),a
        ld      de,s_drivers
        call    puts
        ld      a,1
.next:  ld      (index),a
        ld      c,NX_GDRVR
        ld      hl,SCRATCH
        call    BDOS
        cp      NX_E_IDRVR
        jr      z,.end
        or      a
        jp      nz,fail
        ld      de,s_indent
        call    puts
        ld      a,(SCRATCH+0)           ; slot
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,(SCRATCH+5)           ; version
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,(SCRATCH+6)
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,(SCRATCH+7)
        call    putdec
        ld      a,' '
        call    putc
        ld      hl,SCRATCH+8            ; name, 32 characters
        ld      b,32
.name:  ld      a,(hl)
        call    putc
        inc     hl
        djnz    .name
        call    newline
        ld      a,(index)
        inc     a
        cp      8
        jr      c,.next
.end:

; --- step 3: the driver behind the current drive ----------------------
        ld      a,3
        ld      (step),a
        ld      de,s_drive
        call    puts
        ld      c,_CURDRV
        call    BDOS
        ld      (drive),a
        add     a,'A'
        call    putc
        ld      a,':'
        call    putc
        ld      a,(drive)
        ld      ix,DESC
        ld      hl,SCRATCH
        call    nx_find
        or      a
        jp      nz,fail
        ld      (FIRST),hl
        ld      (FIRST+2),de
        ld      de,s_slot
        call    puts
        ld      a,(DESC+NXD_SLOT)
        call    puthex8
        ld      de,s_bank
        call    puts
        ld      a,(DESC+NXD_BANK)
        call    putdec
        ld      de,s_dev
        call    puts
        ld      a,(DESC+NXD_DEV)
        call    putdec
        ld      de,s_lun
        call    puts
        ld      a,(DESC+NXD_LUN)
        call    putdec
        ld      de,s_first
        call    puts
        ld      hl,(FIRST+2)
        call    puthex16
        ld      hl,(FIRST)
        call    puthex16
        call    newline

; --- step 4: the boot sector, through Nextor and directly -------------
        ld      a,4
        ld      (step),a
        ld      de,s_read
        call    puts
        ld      c,_SETDTA
        ld      de,BUF_A
        call    BDOS
        ld      a,(drive)
        ld      b,1
        ld      hl,0
        ld      de,0                    ; drive-relative sector 0
        ld      c,_RDDRV
        call    BDOS
        or      a
        jp      nz,fail
        call    sec_first               ; SECNUM = FIRST + 0
        ld      ix,DESC
        or      a                       ; Cy = 0: read
        ld      b,1
        ld      hl,BUF_B
        ld      de,SECNUM
        call    nx_rw
        or      a
        jp      nz,fail
        ld      hl,BUF_A
        ld      de,BUF_B
        call    cmp512
        jp      nz,fail_cmp
        ld      de,s_ok
        call    puts

; --- step 5: a file of one sector, and where it is on the device -------
        ld      a,5
        ld      (step),a
        ld      de,s_locate
        call    puts
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
        ld      de,BUF_C
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
        ; From the boot sector read in step 4 (drive-relative sectors):
        ; root = reserved + fats * fatsz; rootsecs = rootent / 16;
        ; data = root + rootsecs. Sector size must be 512.
        ld      hl,(BUF_A+0Bh)
        ld      de,512
        or      a
        sbc     hl,de
        ld      a,0F3h                  ; sector size is not 512
        jp      nz,fail_del
        ld      hl,(BUF_A+0Eh)
        ld      de,(BUF_A+16h)
        ld      a,(BUF_A+10h)
.fats:  add     hl,de
        dec     a
        jr      nz,.fats
        ld      (root),hl
        ld      hl,(BUF_A+11h)
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
        ld      a,0F4h                  ; entry not in the root directory
        jp      z,fail_del
        call    sec_first
        ld      hl,(root)
        call    add32
        ld      hl,(n)
        call    add32
        call    read_b
        jp      nz,fail_del
        ld      hl,BUF_B
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
        ld      a,(BUF_A+0Dh)
.mul:   push    af
        push    hl
        call    add32
        pop     hl
        pop     af
        dec     a
        jr      nz,.mul
        ld      hl,(SECNUM)
        ld      (TARGET),hl
        ld      hl,(SECNUM+2)
        ld      (TARGET+2),hl
        ld      de,s_at
        call    puts
        ld      hl,(TARGET+2)
        call    puthex16
        ld      hl,(TARGET)
        call    puthex16
        ld      de,s_colon
        call    puts
        call    read_b                  ; SECNUM is still the target
        jp      nz,fail_del
        ld      hl,BUF_C
        ld      de,BUF_B
        call    cmp512
        jp      nz,fail_cmp_del
        ld      de,s_ok
        call    puts

; --- step 6: write the sector directly, read the file through Nextor --
        ld      a,6
        ld      (step),a
        ld      de,s_write
        call    puts
        ld      a,0A5h                  ; pattern P2
        call    fill_c
        call    sec_target
        ld      ix,DESC
        scf                             ; Cy = 1: write
        ld      b,1
        ld      hl,BUF_C
        ld      de,SECNUM
        call    nx_rw
        or      a
        jp      nz,fail_del
        ld      b,0
        ld      d,0FFh                  ; flush and invalidate
        ld      c,_FLUSH
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      de,fname
        ld      a,1                     ; open mode: no write
        ld      c,_OPEN
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      a,b
        ld      (fh),a
        ld      de,BUF_B
        ld      hl,512
        ld      c,_READ
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      de,512
        or      a
        sbc     hl,de
        ld      a,0F5h                  ; short read
        jp      nz,fail_del
        ld      a,(fh)
        ld      b,a
        ld      c,_CLOSE
        call    BDOS
        or      a
        jp      nz,fail_del
        ld      hl,BUF_C
        ld      de,BUF_B
        call    cmp512
        jp      nz,fail_cmp_del
        ld      de,fname
        ld      c,_DELETE
        call    BDOS
        or      a
        jp      nz,fail
        ld      de,s_ok
        call    puts

; --- step 7: 600 direct reads with interrupts enabled -----------------
        ld      a,7
        ld      (step),a
        ld      de,s_loop
        call    puts
        ; A fresh reference: Nextor rewrites the boot sector once the volume
        ; has been written to (step 5), so the copy from step 4 is stale.
        ld      c,_SETDTA
        ld      de,BUF_A
        call    BDOS
        ld      a,(drive)
        ld      b,1
        ld      hl,0
        ld      de,0
        ld      c,_RDDRV
        call    BDOS
        or      a
        jp      nz,fail
        ld      hl,(JIFFY)
        ld      (t0),hl
        ld      hl,600
.loop:  ld      (n),hl
        call    sec_first
        call    read_b
        jp      nz,fail
        ld      hl,BUF_A
        ld      de,BUF_B
        call    cmp512
        jp      nz,fail_cmp
        ld      hl,(n)
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(JIFFY)
        ld      de,(t0)
        or      a
        sbc     hl,de
        call    puthex16
        ld      de,s_ticks
        call    puts

pass:
        ld      de,s_pass
        call    puts
        m6_verdict M6_PASS
        ld      b,0
        ld      c,_TERM
        jp      BDOS

; fail — A = error code, (step) = the step that failed.
fail:
        push    af
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

; fail_del / fail_cmp_del — the same, after deleting the test file.
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

; sec_first — SECNUM = FIRST (device sector of the drive's sector 0).
sec_first:
        ld      hl,(FIRST)
        ld      (SECNUM),hl
        ld      hl,(FIRST+2)
        ld      (SECNUM+2),hl
        ret

; sec_target — SECNUM = TARGET.
sec_target:
        ld      hl,(TARGET)
        ld      (SECNUM),hl
        ld      hl,(TARGET+2)
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

; read_b — one sector, SECNUM, directly into BUF_B. Z if ok, else NZ
; with A = the driver's error code.
read_b: ld      ix,DESC
        or      a
        ld      b,1
        ld      hl,BUF_B
        ld      de,SECNUM
        call    nx_rw
        or      a
        ret

; fill_c — BUF_C byte i = (i and 0FFh) xor A.
fill_c: ld      c,a
        ld      hl,BUF_C
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
        ret                             ; Z from "or c"
.diff:  ld      b,(hl)
        ld      c,a
        pop     de                      ; start
        or      a
        sbc     hl,de                   ; offset; NZ
        ret

; --- console helpers, through the BDOS --------------------------------
puts:   ld      c,_STROUT
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

; putdec — A as decimal, no leading zeros.
putdec:
        push    af
        xor     a
        ld      (leading),a
        pop     af
        ld      b,100
        call    .digit
        ld      b,10
        call    .digit
        add     a,'0'
        jp      putc
.digit: ld      c,'0'-1
.sub:   inc     c
        sub     b
        jr      nc,.sub
        add     a,b
        push    af
        ld      a,c
        cp      '0'
        jr      nz,.emit
        ld      a,(leading)
        or      a
        jr      nz,.emit
        pop     af
        ret
.emit:  ld      a,c
        call    putc
        ld      a,1
        ld      (leading),a
        pop     af
        ret

banner:     db  "drvcall: Nextor driver direct call",13,10,'$'
s_version:  db  "1 kernel: Nextor $"
s_drivers:  db  "2 drivers:",13,10,'$'
s_indent:   db  "    slot $"
s_drive:    db  "3 drive $"
s_slot:     db  " slot $"
s_bank:     db  " bank $"
s_dev:      db  " dev $"
s_lun:      db  " lun $"
s_first:    db  " first $"
s_read:     db  "4 read sector 0 via Nextor and directly: $"
s_locate:   db  "5 create M6WRITE.TST, find its sector$"
s_at:       db  " at $"
s_colon:    db  ": $"
s_write:    db  "6 write it directly, read it back via Nextor: $"
s_loop:     db  "7 600 direct reads, interrupts on: $"
s_ticks:    db  "h ticks",13,10,'$'
fname:      db  "\\M6WRITE.TST",0
fname11:    db  "M6WRITE TST"
s_ok:       db  "ok",13,10,'$'
s_pass:     db  "PASS",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
s_diff:     db  " differ at $"
chbuf:      db  0,'$'
step:       db  0
index:      db  0
drive:      db  0
leading:    db  0
fh:         db  0
root:       dw  0
rootsecs:   dw  0
data:       dw  0
cluster:    dw  0
n:          dw  0
t0:         dw  0

; The driver module's two external needs: under Nextor, the BIOS routine and
; the DOS variable.
nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"

        ASSERT $ < 4000h
