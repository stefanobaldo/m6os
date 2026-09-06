; takeover — take the machine from Nextor and call the cartridge's driver
; with the Nextor kernel gone. Under Nextor: find the driver, capture what
; the resident needs, create a file to write into, time a reference loop.
; Then: hooks restored, the resident image copied to page 3, the interrupt
; vector and the subslot stub written to page 0, jump. The resident
; (src/kernel/main.asm) does the rest and halts. Runs in openMSX and on real
; hardware alike; the report is on screen, the verdict in the mailbox.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"

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
E_NOFIL     equ 0D7h            ; .NOFIL: file not found

CALSLT      equ B_CALSLT
SECNUM      equ 8148h           ; 4 bytes: sector number handed to nx_rw

        org     100h

start:
        ld      sp,KT_LSTACK            ; page 2: the DOS stack is under
                                        ; DOSHIM and dies in the takeover
        ld      a,DBG_ASCII
        out     (DBG_MODE),a

; --- step 0: SCREEN 0, while the BIOS can still be asked ----------------
        ld      a,(B_SCRMOD)
        or      a
        jr      z,.screen0
        ld      ix,B_INITXT
        ld      iy,(B_EXPTBL-1)
        call    CALSLT
.screen0:
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
        jr      z,.nextor
        ld      de,s_notnextor
        call    puts
        ld      a,0F1h                  ; MSX-DOS 2, not Nextor
        jp      fail
.nextor:
        ld      a,ixl
        cp      2
        jr      z,.nextor2
        ld      de,s_nextor3
        call    puts
        ld      a,0F2h                  ; Nextor, but not a 2.x kernel
        jp      fail
.nextor2:
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

; --- step 2: every driver in the system, header checked ---------------
        ld      a,2
        ld      (step),a
        ld      de,s_drivers
        call    puts
        ld      a,1
.next:  ld      (index),a
        ld      c,NX_GDRVR
        ld      hl,KT_SCRATCH
        call    BDOS
        cp      NX_E_IDRVR
        jp      z,.end
        or      a
        jp      nz,fail
        ld      de,s_indent
        call    puts
        ld      a,(KT_SCRATCH+0)        ; slot
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,(KT_SCRATCH+5)        ; version
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,(KT_SCRATCH+6)
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,(KT_SCRATCH+7)
        call    putdec
        ld      a,' '
        call    putc
        ; The name: 32 characters, trailing spaces dropped.
        ld      hl,KT_SCRATCH+8+31
        ld      b,32
.trim:  ld      a,(hl)
        cp      ' '
        jr      nz,.named
        dec     hl
        djnz    .trim
.named: ld      hl,KT_SCRATCH+8         ; b = characters to print
.pr:    ld      a,b
        or      a
        jr      z,.header
        ld      a,(hl)
        call    putc
        inc     hl
        dec     b
        jr      .pr
.header:
        ld      a,(KT_SCRATCH+4)        ; flags: bit 7 a Nextor driver
        rlca
        jr      c,.check
        ld      de,s_notdriver
        call    puts
        jr      .listed
.check: call    header_check
        ld      de,s_headerok
        jr      z,.say
        ld      de,s_noheader
.say:   call    puts
.listed:
        ld      a,(index)
        inc     a
        cp      8
        jp      c,.next
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
        ld      de,s_bank
        call    puts
        ld      a,(REC+KR_DRV+NXD_BANK)
        call    putdec
        ld      de,s_dev
        call    puts
        ld      a,(REC+KR_DRV+NXD_DEV)
        call    putdec
        ld      de,s_lun
        call    puts
        ld      a,(REC+KR_DRV+NXD_LUN)
        call    putdec
        ld      de,s_first
        call    puts
        ld      hl,(REC+KR_FIRST+2)
        call    puthex16
        ld      hl,(REC+KR_FIRST)
        call    puthex16
        call    newline

; --- step 4: capture what the resident needs --------------------------
        ld      a,4
        ld      (step),a
        ld      de,s_capture
        call    puts
        ld      ix,REC
        call    nx_capture
        ld      hl,(REC+KR_WALL)
        call    puthex16
        ld      de,s_doshim
        call    puts
        ld      hl,(REC+KR_DOSHIM)
        call    puthex16
        ld      de,s_segs
        call    puts
        ld      hl,REC+KR_SEG64K
        ld      b,4
.seg:   ld      a,(hl)
        push    hl
        call    putdec
        ld      a,' '
        call    putc
        pop     hl
        inc     hl
        djnz    .seg
        ld      de,s_kseg
        call    puts
        ld      a,(REC+KR_CODESEG)
        call    putdec
        ld      a,' '
        call    putc
        ld      a,(REC+KR_DATASEG)
        call    putdec
        ld      de,s_of
        call    puts
        ld      a,(REC+KR_MAPTOTAL)
        call    putdec
        call    newline
        ld      de,s_indent2
        call    puts
        ld      hl,(kimage+K_END-K_BASE) ; the image's end, from its header
        push    hl
        ld      de,K_BASE
        or      a
        sbc     hl,de
        call    putdec16
        ld      de,s_room
        call    puts
        pop     de
        ld      hl,(REC+KR_WALL)
        or      a
        sbc     hl,de                   ; room = wall - end
        ld      a,0F3h                  ; the image does not fit below the wall
        jp      c,fail
        jp      z,fail
        call    putdec16
        call    newline

; --- step 5: the reference sector, through Nextor ---------------------
        ld      a,5
        ld      (step),a
        ld      c,_SETDTA
        ld      de,KT_BUF_A
        call    BDOS
        ld      a,(drive)
        ld      b,1
        ld      hl,0
        ld      de,0                    ; drive-relative sector 0
        ld      c,_RDDRV
        call    BDOS
        or      a
        jp      nz,fail

; --- step 6: the file: last run's write, then a fresh one --------------
        ld      a,6
        ld      (step),a
        ld      de,s_previous
        call    puts
        ld      a,0A5h                  ; P2, what a previous run wrote
        call    fill_c
        ld      de,fname
        ld      a,1                     ; open mode: no write
        ld      c,_OPEN
        call    BDOS
        or      a
        jr      z,.opened
        cp      E_NOFIL
        jp      nz,fail
        ld      de,s_nofile
        call    puts
        jp      .fresh
.opened:
        ld      a,b
        ld      (fh),a
        ld      de,KT_BUF_B
        ld      hl,512
        ld      c,_READ
        call    BDOS
        or      a
        jp      nz,fail
        ld      de,512
        or      a
        sbc     hl,de
        ld      de,s_short
        jr      nz,.verdict
        ld      hl,KT_BUF_C
        ld      de,KT_BUF_B
        call    cmp512
        ld      de,s_yes
        jr      z,.verdict
        ld      de,s_no
.verdict:
        call    puts
        ld      a,(fh)
        ld      b,a
        ld      c,_CLOSE
        call    BDOS
        or      a
        jp      nz,fail
        ld      de,fname
        ld      c,_DELETE
        call    BDOS
        or      a
        jp      nz,fail
.fresh: call    newline
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
        ; From the boot sector read in step 5 (drive-relative sectors):
        ; root = reserved + fats * fatsz; rootsecs = rootent / 16;
        ; data = root + rootsecs. Sector size must be 512.
        ld      hl,(KT_BUF_A+0Bh)
        ld      de,512
        or      a
        sbc     hl,de
        ld      a,0F4h                  ; sector size is not 512
        jp      nz,fail_del
        ld      hl,(KT_BUF_A+0Eh)
        ld      de,(KT_BUF_A+16h)
        ld      a,(KT_BUF_A+10h)
.fats:  add     hl,de
        dec     a
        jr      nz,.fats
        ld      (root),hl
        ld      hl,(KT_BUF_A+11h)
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
        call    read_b
        jp      nz,fail_del
        ld      hl,KT_BUF_B
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
        ld      a,(KT_BUF_A+0Dh)
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
        call    read_b                  ; SECNUM is still the target
        jp      nz,fail_del
        ld      hl,KT_BUF_C
        ld      de,KT_BUF_B
        call    cmp512
        jp      nz,fail_cmp_del
        ld      de,s_ok
        call    puts

; --- step 7: the reference loops, under Nextor ------------------------
; 600 direct reads with a compare, then the same loop without the read; the
; resident repeats both and judges its tick against these (main.asm, step
; 13). The BIOS counts here; k_ticks counts there.
        ld      a,7
        ld      (step),a
        ld      de,s_loop
        call    puts
        ; A fresh reference: Nextor rewrites the boot sector once the volume
        ; has been written to (step 6), so the copy from step 5 is stale.
        ld      c,_SETDTA
        ld      de,KT_BUF_A
        call    BDOS
        ld      a,(drive)
        ld      b,1
        ld      hl,0
        ld      de,0
        ld      c,_RDDRV
        call    BDOS
        or      a
        jp      nz,fail
        ld      hl,read_b
        ld      (loop_fn),hl
        call    loop600
        ld      (REC+KR_TPRE),hl
        call    putdec16
        ld      de,s_ticks
        call    puts
        ld      de,s_loop2
        call    puts
        ld      hl,read_none
        ld      (loop_fn),hl
        call    loop600
        ld      (REC+KR_TPRECMP),hl
        call    putdec16
        ld      de,s_ticks
        call    puts

; --- the takeover -----------------------------------------------------
        ld      de,s_takeover
        call    puts
        ld      a,(B_CSRY)              ; where the screen output stands now
        ld      (REC+KR_CSRY),a
        di
        ld      hl,REC+KR_TIMISAVE      ; the hooks as they were before Nextor
        ld      de,B_HTIMI
        ld      bc,5
        ldir
        ld      hl,REC+KR_FCALSAVE
        ld      de,B_FCALL
        ld      bc,5
        ldir
        ld      hl,kimage               ; the resident, then the record into it
        ld      de,K_BASE
        ld      bc,kimage_end-kimage
        ldir
        ld      hl,REC
        ld      de,K_REC
        ld      bc,KREC_SIZE
        ldir
        ld      hl,(K_END)              ; 55h from the image's end to the wall
        ld      de,(REC+KR_WALL)
        ex      de,hl
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ex      de,hl
        ld      (hl),55h
        ld      d,h
        ld      e,l
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      z,.filled
        ldir
.filled:
        ld      hl,(K_STUB)             ; the subslot stub into page 0
        ld      de,K_SSLOT
        ld      bc,K_SSLOT_LEN
        ldir
        ld      a,0C3h                  ; the interrupt vector
        ld      (K_INTRPT),a
        ld      hl,K_ISR
        ld      (K_INTRPT+1),hl
        ld      sp,(K_END)
        jp      K_ENTRY

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

; header_check — the _GDRVR block at KT_SCRATCH names a slot; switch that
; slot's driver bank in and look for the signature. Z if it is there.
header_check:
        ld      a,(KT_SCRATCH+0)
        ld      (tdesc+NXD_SLOT),a
        ld      hl,4000h
        call    ENASLT
        ei
        ld      a,(NX_K_SIZE)
        ld      (tdesc+NXD_BANK),a
        ld      a,(RAMAD1)
        ld      hl,4000h
        call    ENASLT
        ei
        ld      ix,tdesc
        call    nx_enter
        ld      hl,NX_DRV_SIGN
        ld      de,nx_sign
        ld      b,NX_SIGN_LEN
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.leave
        inc     hl
        inc     de
        djnz    .cmp
        xor     a                       ; Z: found
.leave: push    af
        call    nx_leave
        pop     af
        ret

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

; loop600 — 600 times: SECNUM = first, call (loop_fn), compare KT_BUF_A with
; KT_BUF_B. Returns HL = JIFFY ticks elapsed. Fails through fail.
loop600:
        ld      hl,(B_JIFFY)
        ld      (t0),hl
        ld      hl,600
.loop:  ld      (n),hl
        call    sec_first
        ld      hl,(loop_fn)
        call    call_hl
        jp      nz,fail
        ld      hl,KT_BUF_A
        ld      de,KT_BUF_B
        call    cmp512
        jp      nz,fail_cmp
        ld      hl,(n)
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(B_JIFFY)
        ld      de,(t0)
        or      a
        sbc     hl,de
        ret
call_hl:
        jp      (hl)

; read_none — what the loop calls instead of the driver.
read_none:
        xor     a
        ret

; read_b — one sector, SECNUM, directly into KT_BUF_B. Z if ok, else NZ
; with A = the driver's error code.
read_b: ld      ix,REC+KR_DRV
        or      a
        ld      b,1
        ld      hl,KT_BUF_B
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
        ret                             ; Z from "or c"
.diff:  ld      b,(hl)
        ld      c,a
        pop     de                      ; start
        or      a
        sbc     hl,de                   ; offset; NZ
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

; putdec — A as decimal, no leading zeros.
putdec:
        ld      l,a
        ld      h,0
; putdec16 — HL as decimal, no leading zeros.
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

banner:     db  "takeover: m6 takes the machine from Nextor",13,10,'$'
s_version:  db  "1 kernel: Nextor $"
s_notnextor: db "MSX-DOS 2, not Nextor: not supported",13,10,'$'
s_nextor3:  db  "Nextor 3 kernel: not supported",13,10,'$'
s_drivers:  db  "2 drivers:",13,10,'$'
s_indent:   db  "    slot $"
s_indent2:  db  "    resident $"
s_headerok: db  " header ok",13,10,'$'
s_noheader: db  " NO DRIVER HEADER",13,10,'$'
s_notdriver: db " not a Nextor driver",13,10,'$'
s_drive:    db  "3 drive $"
s_slot:     db  " slot $"
s_bank:     db  " bank $"
s_dev:      db  " dev $"
s_lun:      db  " lun $"
s_first:    db  " first $"
s_capture:  db  "4 wall $"
s_doshim:   db  "h doshim $"
s_segs:     db  "h segs $"
s_kseg:     db  "kernel $"
s_of:       db  " of $"
s_room:     db  " room $"
s_previous: db  "6 previous run wrote P2: $"
s_nofile:   db  "no file$"
s_short:    db  "short file$"
s_yes:      db  "yes$"
s_no:       db  "no$"
s_locate:   db  "  create M6WRITE.TST, find its sector$"
s_at:       db  " at $"
s_colon:    db  ": $"
s_loop:     db  "7 600 direct reads under Nextor: $"
s_loop2:    db  "  the same loop without the call: $"
s_ticks:    db  " ticks",13,10,'$'
s_takeover: db  "-- taking the machine --",13,10,'$'
fname:      db  "\\M6WRITE.TST",0
fname11:    db  "M6WRITE TST"
s_ok:       db  "ok",13,10,'$'
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
loop_fn:    dw  0
tdesc:      ds  NXD_SIZE
REC:        ds  KREC_SIZE

; The driver module's two external needs: under Nextor, the BIOS routine and
; the DOS variable.
nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"
        include "nextor/capture.asm"

; The resident image, copied to K_BASE by the takeover.
kimage:
        incbin  "build/kernel.bin"
kimage_end:

        ASSERT $ < 4000h
