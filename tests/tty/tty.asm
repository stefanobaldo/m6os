; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; tty — the terminal: canonical mode on the keyboard, ttymode, kill,
; signal, the four signals and ^C. Under Nextor: find the driver behind
; the current drive, capture what the resident needs, hand the machine
; over. Then the block below runs as process 0 and drives programs on the
; volume through spawnv — the ones in progs/ — while the harness (tty.tcl)
; presses keys on the matrix at the cues the block leaves in the storage
; segment; on real hardware a person presses them. The block reads the
; kernel's tables directly for what a syscall does not show. The report is
; on screen, the verdict in the mailbox; the harness reads the screen for
; the echo and the test shell's report. Block steps 5-21 are the design's
; nine steps, each cut where a cue is needed.
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

banner:     db  "tty: the terminal, kill, signal and ^C",13,10,'$'
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
; keeps as process 0's page 1 so the block runs where it lies. It runs
; once the kernel has booted and mounted the volumes, as process 0, and
; calls the kernel the way a program does, through K_SYS. Process 0 takes
; no signal and reads the keyboard only to drain it, so every reader and
; every victim below is a program.
tblock:
        ASSERT  tblock >= 4000h         ; in page 1: the loader's boot segment,
                                        ; which the kernel keeps as process 0's

        include "tty/block.asm"

tblock_end:
        ASSERT  $ < 8000h
        ds      KT_BOOT-$,0
kbimage:
        incbin  "build/kboot.bin"
kbimage_end:
        ASSERT  kbimage_end-kbimage <= KB_MAX
