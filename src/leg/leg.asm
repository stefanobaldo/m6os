; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer: what a .COM program finds above its TPA. Two images,
; both carried inside /bin/dos. build/leg.bin, assembled at LEG_BASE, is
; what page 3 holds: dos copies it into the legacy page 3 — a segment of
; the program's own that page 3 shows while it runs — beside a copy of the
; kernel's page 3 from K_HINGE up (the drivers' work areas, Nextor's fixed
; area, the BIOS work area). build/legb.bin, assembled at LEG_BODY, is the
; body — the file functions but _READ, _WRITE and _IOCTL, the messages,
; the entry — which dosenter copies into buffers the block cache lends
; for the program's run, at the end of the kernel's storage segment, and
; which page 2 shows for the length of a call that needs it and at no
; other time: the TPA reaches LEG_BDOS because the body is not above it.
;
; What is in page 3 is what calls the BIOS or the program's own code —
; the console, the device handles, the disk error and abort routines,
; whose hooks and code lie in a TPA that must be whole then — what every
; call runs, and the doors: leg_body, which maps the body, and leg_stin
; and leg_stout, which copy an argument that lies in the program's page 2
; through a staging buffer here, since the body cannot see that page
; (legb.asm decides, by a descriptor a function). The body calls into
; page 3 freely; nothing in page 3 names a label of the body's but
; through leg_body. The body runs with interrupts disabled outside its
; syscalls.
;
; It is the MSX-DOS 2 the program sees, written from the MSX-DOS 2 Program
; Interface and Function specifications: the BDOS entry at LEG_BDOS with
; the CP/M version bytes before it, the CP/M BIOS jump table at LEG_BIOS,
; the page-0 slot routines (RDSLT, WRSLT, CALSLT, ENASLT, CALLF), the
; interrupt trampoline that hands every tick to the BIOS's own handler,
; the sixteen mapper support routines with their jump table and variable
; table and EXTBIO answering for them, and the functions themselves. The
; console goes through the BIOS's CHPUT, CHGET and CHSNS by CALSLT, as
; under MSX-DOS; what needs the kernel — a segment, the clock, and in
; time the files — crosses the hinge as a syscall (leg_sys). The layer
; keeps its variables in its own image and its own stack for a BDOS call,
; saving the program's SP as MSX-DOS does.
;
; The kernel knows LEG_BASE, LEG_BDOS, LEG_VEC, LEG_VARS with its fields,
; LEG_PARAMS and LEG_BIOS (kernel.inc), and nothing else about this file.
        include "kernel/kernel.inc"

        include "leg/leg.inc"

LEG_STACK       equ 192         ; the layer's own stack for a BDOS call
LEG_ISTACK      equ 128         ; and the trampoline's, for a tick taken
                                ; while the program's stack is not in
                                ; page 3 (leg_isr)
; The handle table (legf.asm): LEG_NHAND rows of three bytes.
LEG_NHAND       equ 16
HN_FD            equ 0           ; a descriptor 3-7, a device HD_*, or free
HN_FLAGS         equ 1           ; HF_*
HN_LEVEL         equ 2           ; the _FORK level it was opened at
HF_NOWR         equ 1           ; no writes — the open mode's own bits
HF_NORD         equ 2           ; no reads
HF_INH          equ 4           ; inheritable
HF_FCB          equ 08h         ; taken by an FCB (legc.asm, legk.asm)
HF_ASCII        equ 20h         ; a device in ASCII mode
HF_EOF          equ 40h         ; the last read met the end
HD_CON          equ 80h         ; the console
HD_NUL          equ 81h         ; nothing
HD_DEAD         equ 82h         ; deleted under a duplicate: .HDEAD
HD_FREE         equ 0FFh
; A descriptor's row (leg_fdrow): where its file is, for the handle
; functions that need a name.
FR_DRIVE        equ 0           ; the physical drive
FR_CLUS         equ 1           ; 2: its directory's cluster
FR_ALIAS        equ 3           ; 13: its 8.3 alias, 0-terminated
FR_SIZE         equ 16
; An FCB row's side table (leg_fpos): where the kernel's descriptor
; stands, so a record function seeks only when the record is elsewhere,
; and the stamp the FCB must carry to be believed (legc.asm).
FP_POS          equ 0           ; 4: the position, FFFFFFFFh = unknown
FP_STAMP        equ 4
FP_SIZE         equ 5
; A file info block's internal part (DOS2-PIS §3.4: bytes 26-63).
FI_DRIVE        equ 26          ; the physical drive searched
FI_CLUS         equ 27          ; 2: the directory's cluster
FI_POS          equ 29          ; 4: the entry index the search resumes at
FI_PAT          equ 33          ; 11: the pattern, expanded
FI_ATTR         equ 44          ; the attributes wanted
FI_LOG          equ 45          ; the logical drive named, 0 = A:
LEG_PATHMAX     equ 144         ; a translated path and its 0
LEG_NAMEMAX     equ 32          ; a last item and its 0
LEG_LINEMAX     equ 115         ; a line _READ takes from the console
LEG_ENVMAX      equ 256         ; the environment store
LB_SDE          equ 255         ; the staging buffers (legb.asm): the most
LB_SHL          equ 128         ;   of DE's argument and of HL's

; leg_sys n — a syscall through the hinge: the arguments in A, HL, DE,
; BC as the syscall wants them; the result in HL, and AF as the syscall
; left it, CF and the errno included.
    macro leg_sys n
        exx
        ld      c,n
        exx
        call    leg_syscall
    endm

; leg_sysx n — the same through leg_xsys (legf.asm), which keeps the
; arguments for the program's disk error routine to have the call
; repeated.
    macro leg_sysx n
        exx
        ld      c,n
        exx
        call    leg_xsys
    endm

        OUTPUT  "build/leg.bin"
        org     LEG_BASE
        db      0,16h,0,0,0,0           ; CP/M 2.2's version and serial
        jp      leg_bdos                ; LEG_BDOS: the TPA's top
        block   LEG_VEC-$
        jp      leg_ret                 ; +0: not used
        jp      leg_ret                 ; +3: a syscall's return
        jp      leg_isr                 ; +6: 0038h while this page is in
        jp      leg_extbio              ; +9: FFCAh
        jp      leg_rdslt               ; +12: 000Ch
        jp      leg_wrslt               ; +15: 0014h
        jp      leg_calslt              ; +18: 001Ch
        jp      leg_enaslt              ; +21: 0024h
        jp      leg_callf               ; +24: 0030h
        block   LEG_VARS-$
leg_segs:       db 0,0,0                ; LEG_SEGS: pages 0-2, the PUT_Pn shadow
leg_seg3:       db 0                    ; LEG_SEG3
leg_drive:      db 0                    ; LEG_DRIVE
leg_started:    db 0                    ; LEG_STARTED
leg_fd:         db 0                    ; LEG_FD: the program's file
leg_size:       dw 0                    ; LEG_SIZE: its length
leg_rampri:     db 0                    ; LEG_RAMPRI, LEG_RAMSEC: the RAM's
leg_ramsec:     db 0FFh                 ;   slot in pages 1 and 2
leg_stseg:      db 0                    ; LEG_STSEG: where the body is
        ASSERT  leg_rampri == LEG_RAMPRI && leg_stseg == LEG_STSEG
        block   LEG_PARAMS-$
leg_params:     ds 128                  ; the tail as typed
        block   LEG_BIOS-$
        jp      leg_wboot               ; WBOOT
        jp      leg_wboot               ; WBOOT
        jp      b_const                 ; CONST
        jp      b_conin                 ; CONIN
        jp      b_conout                ; CONOUT
        jp      b_ret                   ; LIST
        jp      b_ret                   ; PUNCH
        jp      b_ret                   ; READER
        jp      b_ret                   ; HOME
        jp      b_ret                   ; SELDSK
        jp      b_ret                   ; SETTRK
        jp      b_ret                   ; SETSEC
        jp      b_ret                   ; SETDMA
        jp      b_ret                   ; READ
        jp      b_ret                   ; WRITE
        jp      b_lstst                 ; LISTST
        jp      b_ret                   ; SECTRAN

; ---------------------------------------------------------------------
; Entering and leaving

; leg_go — the end of the entry (legi.asm), outside the body: the
; program's page 2 back, the stack where MSX-DOS puts it with 0000h under
; it so that a ret ends the program through the jump there, and into the
; program with interrupts enabled.
leg_go: call    leg_bout
        ld      hl,0                    ; a ret from the program is jp 0
        push    hl
        ld      d,h
        ld      e,l
        ld      b,h
        ld      c,l
        xor     a
        ei
        jp      P0_PROG

; leg_syscall — the number in C', the arguments in A, HL, DE, BC: the
; kernel's page 3 in through the first stub, the syscall, and back
; through the second to leg_ret. The program's stack is left where it
; is; the crossing runs on the hinge's. The kernel is told what pages 0-2
; hold, and reaches the call's buffers through that: the program's
; segments — or, from the body (leg_inb bit 1), the storage segment as
; page 2, which is where the body's own buffers are; an argument of the
; program's is never in page 2 there, since the door has staged it.
; Returns the result in HL and AF (CF and the errno as the syscall left
; them), with interrupts enabled — or, in a call of the body's (bit 0),
; disabled and the body mapped again, since the kernel has put back the
; page 2 it was told of, or the program's after a switch.
leg_syscall:
        di
        ld      (leg_usp2),sp
        ld      sp,K_HINGE_SP
        ex      af,af'                  ; the stub uses A
        ld      a,(leg_inb)
        rra
        call    nc,leg_ramin            ; (the body's call has done it)
        ld      ix,(leg_segs)           ; IXL = page 0, IXH = page 1
        ld      a,(leg_inb)
        and     2
        ld      a,(leg_segs+2)
        jr      z,.p2
        ld      a,(leg_stseg)
.p2:    ld      iyh,a                   ; IYH = page 2
        jp      K_HINGE
leg_ret:                                ; from the second stub, di, AF in AF'
        ld      a,(leg_started)
        or      a
        jr      z,.first
        ld      sp,(leg_usp2)
        ld      a,(leg_inb)
        rra
        jr      c,.body
        call    leg_ramout
        ex      af,af'
        ei
        ret
.body:  ld      a,(leg_stseg)
        out     (0FEh),a
        ex      af,af'
        ret
.first: inc     a                       ; from dosenter: the entry, which is
        ld      (leg_started),a         ; the body's; the program's page 2
        ld      sp,LEG_BDOS-8           ; is what its load reads into
        call    leg_bin
        jp      leg_entry

; leg_bin — A = leg_inb's value: a call of the body's begins — interrupts
; off, pages 1 and 2 in the RAM's slot, the storage segment in page 2.
; leg_bout — it ends, or stands aside for the program's code: the
; program's page 2 back, and its slots. Both preserve all but AF; neither
; touches the interrupt flag but leg_bin's di.
leg_bin:
        di
        ld      (leg_inb),a
        call    leg_ramin
        ld      a,(leg_stseg)
        out     (0FEh),a
        ret
leg_bout:
        xor     a
        ld      (leg_inb),a
        ld      a,(leg_segs+2)
        out     (0FEh),a
        ; fall through

; leg_ramout — the slots leg_ramin found, back. leg_ramin — pages 1 and 2
; in the RAM's slot, what was there kept: a program may call the system
; with either page showing another slot — an editor that keeps the
; SUB-ROM's neighbour in page 2 does — and the kernel's window, its
; storage gate and the layer's body are all RAM in those two pages. The
; secondary register is the RAM's primary slot's, which page 3 shows, so
; it is written directly. Interrupts are off. Both preserve all but AF.
leg_ramout:
        ld      a,(leg_ramsec)
        inc     a
        jr      z,.pri
        ld      a,(leg_svff)
        ld      (0FFFFh),a
.pri:   ld      a,(leg_sva8)
        out     (0A8h),a
        ret
leg_ramin:
        push    hl
        ld      hl,leg_rampri
        in      a,(0A8h)
        ld      (leg_sva8),a
        and     0C3h
        or      (hl)
        out     (0A8h),a
        inc     hl                      ; leg_ramsec
        ld      a,(hl)
        inc     a
        jr      z,.done                 ; not expanded: no register there
        ld      a,(0FFFFh)
        cpl
        ld      (leg_svff),a
        and     0C3h
        or      (hl)
        ld      (0FFFFh),a
.done:  pop     hl
        ret

; leg_body — the door: a BDOS function whose handler is the body's, from
; leg_bdos with the registers the program's and .done as the return. The
; body in, lb_call (legb.asm) stages what must be staged and runs the
; handler, the body out.
leg_body:
        push    af
        ld      a,3
        call    leg_bin
        pop     af
        call    lb_call
        push    af
        call    leg_bout
        pop     af
        ret

; leg_stin — from the body, which cannot see the program's page 2: HL =
; an address of the program's, DE = a staging buffer, BC = the most to
; copy; A = SI_BLOCK for all of it, SI_STR for a string — to its 0, one
; forced into the last byte when none comes — SI_PATH for a string or, a
; first byte of FFh, a file info block's 64 bytes. leg_stout — HL = the
; staging buffer, DE = the program's address, BC = the bytes. Corrupt AF,
; BC, DE, HL.
SI_BLOCK        equ 0
SI_STR          equ 1
SI_PATH         equ 2
leg_stin:
        push    af
        ld      a,(leg_segs+2)
        out     (0FEh),a
        pop     af
        or      a
        jr      z,.block
        dec     a
        jr      z,.str
        ld      a,(hl)
        inc     a
        jr      nz,.str
        ld      bc,64
.block: ldir
        jr      leg_stback
.str:   ld      a,(hl)
        ld      (de),a
        or      a
        jr      z,leg_stback
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.str
        dec     de
        ld      (de),a                  ; a = 0: the string cut short
        jr      leg_stback
leg_stout:
        ld      a,(leg_segs+2)
        out     (0FEh),a
        ldir
leg_stback:
        ld      a,(leg_stseg)
        out     (0FEh),a
        ret

; leg_term — A = the termination code: the BDOS call in progress left,
; the program's stack back; the abort routine, if the program defined
; one (DE = its address, _DEFAB), with A = the code and B = the error
; that caused it; then jp 0, as MSX-DOS 2 ends a program: whatever the
; jump there leads to runs — leg_wboot, or the code of a program that
; aimed the WBOOT jump at itself to run another and come back. Never
; returns.
leg_term:
        ld      b,0
leg_term2:                              ; B = the error that caused it
        ld      (leg_code),a
        ld      a,b
        ld      (leg_code2),a
        ld      a,(leg_inb)             ; from the body: the program's page
        or      a                       ; 2 and its slots, for its routine
        call    nz,leg_bout
        ld      hl,leg_nest             ; no call is in progress any more
        xor     a
        cp      (hl)
        ld      (hl),a
        jr      z,.user
        ld      sp,(leg_usp)
.user:  ei
        ld      hl,(leg_defab)
        ld      a,h
        or      l
        jp      z,0
        ld      de,0                    ; the routine returns to jp 0
        push    de
        ld      a,(leg_code2)
        ld      b,a
        ld      a,(leg_code)
        jp      (hl)

; leg_wboot — the BIOS table's WBOOT, where jp 0 leads: the crossing
; that ends the process, with the code of the _TERM that led here as its
; status — 0 for a program that never called one.
leg_wboot:
        di
        ld      sp,K_HINGE_SP
        call    leg_ramin               ; whatever slots the program ends
        ld      a,(leg_code)            ; with, the kernel's window is RAM
        exx
        ld      c,LEG_EXIT
        exx
        ex      af,af'
        jp      K_HINGE

; leg_abort — A = D_STOP or D_CTRLC: the program ends with it, as
; MSX-DOS ends one whose console function met the key.
leg_abort:
        ld      (leg_lasterr),a
        jp      leg_term

; ---------------------------------------------------------------------
; The BDOS

; leg_bdos — CALL 0005h: C = the function. The program's SP kept, the
; layer's stack taken, IX and IY preserved as the specification promises.
; The flags come back set from A, as MSX-DOS 2 returns them.
; Functions below 40h return A = L and B = H; the rest an error code in
; A. A function the layer does not serve answers .IBDOS. A disk error
; routine may call the BDOS from inside a call: the layer's stack is
; kept then, not taken again (leg_nest).
leg_bdos:
        ld      (leg_hl),hl             ; the program's HL: an argument
        ld      hl,leg_nest
        inc     (hl)
        dec     (hl)
        jr      nz,.on
        ld      (leg_usp),sp
        ld      sp,leg_stack_top
.on:    inc     (hl)
        push    ix
        push    iy
        push    af                      ; the program's A: an argument too
        ld      a,c
        cp      32h
        jr      c,.low
        cp      40h
        jr      c,.isbfn
        cp      71h
        jr      nc,.isbfn
        sub     40h
        ld      hl,leg_tab_hi
        jr      .go
.low:   ld      hl,leg_tab_lo
.go:    add     a,a
        add     a,l
        ld      l,a
        jr      nc,.nc
        inc     h
.nc:    ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      (leg_fn),hl             ; the handler
        ld      a,c
        ld      (leg_fnum),a            ; and its function, for the door
        pop     af
        ld      hl,.done
        push    hl                      ; where the handler returns
        ld      hl,(leg_hl)
        push    hl
        ld      hl,(leg_fn)
        bit     6,h                     ; page 3 is C000h up; the body's
        jr      nz,.here                ; handlers are in page 2: the door
        ld      hl,leg_body
.here:  ex      (sp),hl                 ; the handler under it, HL the program's
        ret                             ; into the handler
.done:  pop     iy
        pop     ix
        push    hl                      ; the result
        ld      hl,leg_nest
        dec     (hl)
        pop     hl
        jr      nz,.ret
        ld      sp,(leg_usp)
.ret:   or      a                       ; the flags as A has them: a program
        ei                              ; may branch on Z with no test of A
        ret
.isbfn: pop     af
        ld      a,D_IBDOS
        ld      (leg_lasterr),a
        ld      l,a
        ld      h,0
        ld      b,h
        jr      .done

leg_tab_lo:                             ; 00h-31h
        dw      f_term0, f_conin, f_conout, f_auxin, f_auxout, f_auxout
        dw      f_dirio, f_dirin, f_innoe, f_strout, f_bufin, f_const
        dw      f_cpmver, f_dskrst, f_seldsk
        dw      f_fopen, f_fclose, f_sfirst, f_snext, f_fdel, f_rdseq
        dw      f_wrseq, f_fmake, f_fren    ; 0Fh-17h: FCBs
        dw      f_login, f_curdrv, f_setdta, f_alloc
        dw      f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos ; 1Ch-20h
        dw      f_rdrnd, f_wrrnd, f_fsize, f_setrnd, f_ibdos, f_wrblk
        dw      f_rdblk, f_wrrnd, f_ibdos   ; 21h-29h: FCBs (28h = 22h)
        dw      f_gdate, f_sdate, f_gtime, f_stime, f_verify
        dw      f_ibdos, f_ibdos            ; 2Fh, 30h: absolute sectors
        dw      f_dparm
leg_tab_hi:                             ; 40h-70h
        dw      f_ffirst, f_fnext, f_fnew, f_open, f_create, f_close
        dw      f_ensure, f_dup, f_read, f_write, f_seek, f_ioctl
        dw      f_htest, f_delete, f_rename, f_move, f_attr, f_ftime
        dw      f_hdelete, f_hrename, f_hmove, f_hattr, f_hftime
        dw      f_getdta, f_getvfy, f_getcd, f_chdir, f_parse, f_pfile
        dw      f_chkchr, f_wpath, f_flush, f_fork, f_join, f_term
        dw      f_defab, f_defer, f_error, f_explain
        dw      f_ibdos, f_ibdos, f_ibdos   ; 67h-69h: format, RAM disk,
        dw      f_assign, f_genv, f_senv, f_fenv, f_dskchk, f_dosver
        dw      f_redir

f_ibdos:
        ld      a,D_IBDOS
        ld      (leg_lasterr),a
        ld      l,a
        ld      h,0
        ld      b,h
        ret

; _TERM0 (00h) and _TERM (62h): B = the code.
f_term0:
        ld      b,0
f_term: ld      a,b
        jp      leg_term

; _DEFAB (63h): DE = the abort routine's address, 0 for none.
f_defab:
        ld      (leg_defab),de
        xor     a
        ret

; _ERROR (65h): B = the last error code.
f_error:
        ld      a,(leg_lasterr)
        ld      b,a
        xor     a
        ret

; _DOSVER (6Fh): the kernel and MSXDOS2.SYS versions, 2.31 both; not
; Nextor — the handshake in B, HL, DE is not answered, and IX comes back
; as it went.
f_dosver:
        ld      bc,0231h
        ld      de,0231h
        xor     a
        ret

; _CPMVER (0Ch): HL = 0022h, CP/M 2.2.
f_cpmver:
        ld      hl,0022h
        ld      a,l
        ld      b,h
        ret

; _GTIME (2Ch): the clock through the kernel — H = hours, L = minutes,
; D = seconds (the FAT field holds halves, so even), E = 0.
f_gtime:
        leg_sys SYS_TIME                ; HL = FAT date, DE = FAT time
        ld      a,d
        rrca
        rrca
        rrca
        and     1Fh
        ld      h,a                     ; hours
        ld      a,d
        and     7
        ld      b,a
        ld      a,e
        rlca
        rlca
        rlca
        and     7
        or      a
        ld      c,a
        ld      a,b
        add     a,a
        add     a,a
        add     a,a
        or      c
        ld      l,a                     ; minutes
        ld      a,e
        and     1Fh
        add     a,a
        ld      d,a                     ; seconds
        ld      e,0
        xor     a
        ret

; ---------------------------------------------------------------------
; The console

; _CONOUT (02h): E to the screen, after the break check.
f_conout:
        call    leg_break
        ld      a,e
        call    leg_chput
        xor     a
        ld      l,a
        ld      b,a
        ret

; _STROUT (09h): DE -> a $-terminated string.
f_strout:
        call    leg_break
.next:  ld      a,(de)
        cp      '$'
        jr      z,.done
        call    leg_chput
        inc     de
        jr      .next
.done:  xor     a
        ld      l,a
        ld      b,a
        ret

; _CONIN (01h): a key, echoed. _INNOE (08h): a key, not echoed. _DIRIN
; (07h): a key, no echo and no break check.
f_conin:
        call    leg_break
        call    leg_chget
        push    af
        call    leg_chput
        pop     af
        jr      f_key
f_innoe:
        call    leg_break
f_dirin:
        call    leg_chget
f_key:  ld      l,a
        ld      b,0
        ret

; _DIRIO (06h): E = FFh: a key if one waits, else 0; otherwise E to the
; screen.
f_dirio:
        ld      a,e
        inc     a
        jr      nz,.out
        call    leg_chsns
        jr      z,.none
        call    leg_chget
        jr      f_key
.none:  xor     a
        jr      f_key
.out:   ld      a,e
        call    leg_chput
        xor     a
        jr      f_key

; _CONST (0Bh): A = FFh when a key waits, 0 when none.
f_const:
        call    leg_break
        call    leg_chsns
        ld      a,0
        jr      z,f_key
        ld      a,0FFh
        jr      f_key

; _BUFIN (0Ah): DE -> a buffer — the most it holds, then the count the
; layer fills in, then the bytes. BS and DEL take a byte back, RET ends
; the line and is echoed as a carriage return; anything under a blank is
; dropped. ^C ends the program. The buffer's address is kept in memory:
; the console routines corrupt IX and IY.
f_bufin:
        ld      (bi_buf),de
        ld      c,0                     ; the count
.key:   call    leg_chget
        cp      0Dh
        jr      z,.end
        cp      3
        jr      z,.ctrlc
        cp      8
        jr      z,.bs
        cp      7Fh
        jr      z,.bs
        cp      ' '
        jr      c,.key
        ld      b,a
        ld      hl,(bi_buf)
        ld      a,c
        cp      (hl)
        jr      nc,.key                 ; full
        inc     hl
        inc     hl
        ld      a,c
        add     a,l
        ld      l,a
        adc     a,h
        sub     l
        ld      h,a                     ; hl -> the byte's place
        ld      (hl),b
        inc     c
        ld      a,b
        call    leg_chput
        jr      .key
.bs:    ld      a,c
        or      a
        jr      z,.key
        dec     c
        ld      a,8
        call    leg_chput
        ld      a,' '
        call    leg_chput
        ld      a,8
        call    leg_chput
        jr      .key
.end:   ld      hl,(bi_buf)
        inc     hl
        ld      (hl),c
        ld      a,0Dh
        call    leg_chput
        xor     a
        ld      l,a
        ld      b,a
        ret
.ctrlc: ld      a,D_CTRLC
        jp      leg_abort

; leg_break — CTRL+STOP held, or a ^C waiting in the BIOS's buffer: the
; program ends with .STOP or .CTRLC. Preserves BC, DE, HL.
leg_break:
        push    hl
        push    de
        push    bc
        ld      ix,B_BREAKX
        call    leg_bios
        jr      c,.stop
        call    leg_chsns
        jr      z,.none
        ld      hl,(B_GETPNT)
        ld      a,(hl)
        cp      3
        jr      nz,.none
        call    leg_chget               ; the ^C taken
        pop     bc
        pop     de
        pop     hl
        ld      a,D_CTRLC
        jp      leg_abort
.stop:  pop     bc
        pop     de
        pop     hl
        ld      a,D_STOP
        jp      leg_abort
.none:  pop     bc
        pop     de
        pop     hl
        ret

; leg_chput — A to the screen through the BIOS. leg_chget — A = the next
; key, waiting for one. leg_chsns — Z when no key waits. All preserve
; BC, DE, HL.
leg_chput:
        ld      ix,B_CHPUT
        jr      leg_bios
leg_chget:
        ld      ix,B_CHGET
        jr      leg_bios
leg_chsns:
        ld      ix,B_CHSNS
leg_bios:
        push    hl
        push    de
        push    bc
        ld      iy,(B_EXPTBL-1)         ; the BIOS's slot in IYh
        call    leg_calslt
        pop     bc
        pop     de
        pop     hl
        ei
        ret

; The CP/M BIOS table's console entries: C = the character out, A in.
b_const:
        call    leg_chsns
        ld      a,0
        ret     z
        ld      a,0FFh
        ret
b_conin:
        jp      leg_chget
b_conout:
        ld      a,c
        jp      leg_chput
b_lstst:
        xor     a
b_ret:  ret

; ---------------------------------------------------------------------
; Slots: the page-0 entry points, and the trampoline

; leg_enaslt — A = a slot id (E000SSPP), HL = an address in page 0, 1 or
; 2: that slot into the page, SLTTBL kept true. Returns with interrupts
; disabled. Corrupts AF, BC, DE, HL.
;
; An expanded slot's subslot register lives at FFFFh of its primary slot,
; so page 3 must show that primary while it is written. When the target's
; primary is the one page 3 shows already — the RAM's, which is how RAM
; comes back into page 0 after a BIOS call — the register is written from
; here, with page 3 untouched. Otherwise the stub at K_SSLOT, in page 0's
; RAM, switches page 3 for the write and back, so page 0 must still be
; RAM then: the subslot goes first and the primary last, and the one
; switch this cannot do — a foreign expanded slot into page 0 while page
; 0 is not RAM — is one MSX-DOS cannot do either.
leg_enaslt:
        di
        ld      c,a                     ; c = slot id
        ld      a,h
        rlca
        rlca
        and     3
        add     a,a
        ld      b,a                     ; the shift for this page
        ld      a,c
        and     3
        ld      e,a                     ; primary slot bits
        ld      a,c
        rrca
        rrca
        and     3
        ld      h,a                     ; subslot bits
        ld      d,3                     ; mask
        ld      a,b
        or      a
        jr      z,.placed
.shift: sla     e
        sla     d
        sla     h
        dec     a
        jr      nz,.shift
.placed:                                ; d, e, h are in the page's position
        bit     7,c
        jr      z,.primary
        push    de
        in      a,(PPI_A)
        ld      b,a                     ; b = primary register, to restore
        rlca
        rlca
        and     3                       ; page 3's primary
        ld      l,a
        ld      a,c
        and     3
        cp      l
        jr      z,.direct               ; the same primary: FFFFh is its
        ld      a,b
        and     3Fh
        ld      l,a
        ld      a,c
        and     3
        rrca
        rrca                            ; primary slot in page 3's bits
        or      l
        ld      e,a                     ; e = the register with the target
                                        ;     primary in page 3
        ld      a,d
        cpl
        ld      d,a                     ; d = complemented mask
        call    K_SSLOT                 ; l = the new subslot register value
        jr      .table
.direct:
        ld      a,(0FFFFh)
        cpl                             ; the register reads back inverted
        ld      l,a
        ld      a,d
        cpl
        and     l
        or      h
        ld      (0FFFFh),a
        ld      l,a
.table: ld      a,c
        and     3
        add     a,low B_SLTTBL          ; no carry: C5h + 3
        ld      e,a
        ld      d,high B_SLTTBL
        ld      a,l
        ld      (de),a                  ; SLTTBL[primary] = new value
        pop     de
.primary:
        in      a,(PPI_A)
        ld      b,a
        ld      a,d
        cpl
        and     b
        or      e
        out     (PPI_A),a
        ret

; leg_curslot — A = a page 0-2: A = the slot id in it now, from the
; primary register and, for an expanded slot, SLTTBL. Corrupts BC, DE, HL.
leg_curslot:
        add     a,a
        ld      c,a                     ; the shift: 0, 2 or 4
        in      a,(PPI_A)
        ld      d,a
        ld      a,c
        or      a
        jr      z,.p
.s:     srl     d
        dec     a
        jr      nz,.s
.p:     ld      a,d
        and     3
        ld      e,a                     ; the primary
        ld      d,0
        ld      hl,B_EXPTBL
        add     hl,de
        bit     7,(hl)
        ld      a,e
        ret     z                       ; not expanded
        ld      hl,B_SLTTBL
        add     hl,de
        ld      d,(hl)                  ; the subslot register's value
        ld      a,c
        or      a
        jr      z,.q
.t:     srl     d
        dec     a
        jr      nz,.t
.q:     ld      a,d
        and     3
        add     a,a
        add     a,a
        or      e
        or      80h
        ret

; leg_calslt — IYh = a slot id, IX = an address: the routine there called
; with AF, BC, DE, HL as they are, the slot that was in the page put back
; after, the routine's registers and flags returned; IX and IY are
; corrupted. An address in page 3 is called in place. Interrupts are
; disabled around the switches and left as the routine left them. Nothing
; is kept in a variable across the call, because the interrupt trampoline
; comes through here too and a tick inside a CALSLT must not rewrite the
; one in progress: the page and the slot that was there ride in IY up to
; the call and on the caller's stack, under the routine's return, across
; it — the routine may use IY, and the SUB-ROM's do.
leg_calslt:
        push    hl
        push    de
        push    bc
        push    af
        ld      a,iyh
        ld      c,a                     ; the target slot
        push    ix
        pop     hl
        ld      a,h
        rlca
        rlca
        and     3                       ; the page
        ld      iyh,a
        cp      3
        jr      z,.call
        push    bc
        call    leg_curslot             ; a = the slot in the page now
        pop     bc
        ld      iyl,a
        ld      a,c
        push    ix
        pop     hl
        call    leg_enaslt
.call:  pop     af
        pop     bc
        pop     de
        pop     hl
        push    iy                      ; the page, and the slot to put back
        push    hl
        ld      hl,.back
        ex      (sp),hl                 ; .back pushed, hl as it was
        jp      (ix)
.back:  pop     iy
        push    af
        push    hl
        push    de
        push    bc
        ld      a,iyh
        cp      3
        jr      z,.done
        di
        rrca
        rrca
        ld      h,a                     ; page * 4000h
        ld      l,0
        ld      a,iyl                   ; the slot that was there
        call    leg_enaslt
.done:  pop     bc
        pop     de
        pop     hl
        pop     af
        ret

; leg_callf — RST 30h: the slot and the address follow the call.
leg_callf:
        ex      (sp),hl
        push    af
        ld      a,(hl)
        ld      iyh,a
        inc     hl
        ld      a,(hl)
        ld      ixl,a
        inc     hl
        ld      a,(hl)
        ld      ixh,a
        inc     hl
        pop     af
        ex      (sp),hl
        jp      leg_calslt

; leg_rdslt — A = a slot id, HL = an address: A = the byte there.
; leg_wrslt — the same with E written there. Both through the slot in
; and out, page 3 read or written in place, interrupts disabled from the
; first instruction and on return, as the BIOS's are — which is what
; keeps their few variables safe from the trampoline.
leg_rdslt:
        di
        ld      (rs_val),a
        ld      a,0
        jr      rs_go
leg_wrslt:
        di
        ld      (rs_val),a
        ld      a,1
rs_go:  ld      (rs_dir),a
        push    bc
        push    de
        push    hl
        ld      a,h
        rlca
        rlca
        and     3
        ld      (cs_page),a
        cp      3
        jr      z,.inplace
        call    leg_curslot
        ld      (cs_slot),a
        pop     hl
        push    hl
        ld      a,(rs_val)
        call    leg_enaslt
.inplace:
        pop     hl
        pop     de
        ld      a,(rs_dir)
        or      a
        jr      nz,.write
        ld      a,(hl)
        ld      (rs_val),a
        jr      .back
.write: ld      (hl),e
.back:  push    de
        push    hl
        ld      a,(cs_page)
        cp      3
        jr      z,.done
        rrca
        rrca
        ld      h,a                     ; page * 4000h
        ld      l,0
        ld      a,(cs_slot)
        call    leg_enaslt
.done:  pop     hl
        pop     de
        pop     bc
        ld      a,(rs_val)
        ret

; leg_isr — 0038h while this page is in: the BIOS's own interrupt entry
; through CALSLT, which scans the keyboard, counts JIFFY and runs the
; hooks in this copy of its work area.
;
; The BIOS is called with its own slot in page 0, so a program whose
; stack is in pages 0-2 — XCOPY puts its at 2800h, and nothing forbids
; it — would lose the stack under the tick. The trampoline moves to a
; stack of its own in this page first, as MSX-DOS's page-0 handler does,
; and keeps the interrupted SP on it. A stack already in page 3 stays
; where it is: that is a tick during a BDOS call, or a tick inside a
; hook that enabled interrupts again, and the frame in progress must not
; be written over.
leg_isr:
        di
        ld      (leg_isp),sp
        push    af
        ld      a,(leg_isp+1)
        cp      0C0h                    ; page 3: the stack stays there
        jr      c,.move
        pop     af
        call    .tick
        ei
        reti
.move:  pop     af
        ld      sp,leg_istack_top
        push    hl
        ld      hl,(leg_isp)
        ex      (sp),hl                 ; the interrupted SP under it
        call    .tick
        ld      (leg_isp),hl
        pop     hl
        ld      sp,hl
        ld      hl,(leg_isp)
        ei
        reti
.tick:  push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ld      iy,(B_EXPTBL-1)
        ld      ix,0038h
        call    leg_calslt
        di
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; ---------------------------------------------------------------------
; The mapper support routines (DOS2-PIS §5)

leg_maptab:
        jp      m_all_seg
        jp      m_fre_seg
        jp      m_rd_seg
        jp      m_wr_seg
        jp      m_cal_seg
        jp      m_calls
        jp      m_put_ph
        jp      m_get_ph
        jp      m_put_p0
        jp      m_get_p0
        jp      m_put_p1
        jp      m_get_p1
        jp      m_put_p2
        jp      m_get_p2
        jp      m_put_p3
        jp      m_get_p3

; The variable table: the primary mapper's slot, its segments, the free
; ones, the system's, the user's, three zeros; then a zero entry.
leg_mapvar:
        db      0,0,0,0,0,0,0,0
        db      0,0,0,0,0,0,0,0

; ALL_SEG — A = 0 (user) or 1 (system), B = 0 (the primary mapper) or a
; slot and how to try it: A = the segment, B = its mapper's slot — 0 when
; B came as 0, as MSX-DOS 2 answers; a program keeps that byte and hands
; it to ENASLT — CF when none is free. There is one mapper: whatever slot
; is asked for, the segment is the primary's. Every segment is the
; program's and goes at its exit. Corrupts AF, BC and nothing else: a
; crossing leaves IX and IY undefined, and a program keeps its own in
; them across a mapper routine, which is not a BDOS call.
m_all_seg:
        push    hl
        push    de
        push    ix
        push    iy
        push    bc
        leg_sys SYS_SEGALLOC
        pop     bc
        pop     iy
        pop     ix
        jr      c,.none
        ld      a,b
        or      a
        jr      z,.slot
        ld      a,(leg_mapvar+0)
.slot:  ld      b,a
        ld      a,l
        ld      hl,leg_mapvar+2
        dec     (hl)
        inc     hl
        inc     hl
        inc     (hl)
        or      a
.out:   pop     de
        pop     hl
        ret
.none:  scf
        jr      .out

; FRE_SEG — A = a segment: freed; CF when it is not the program's.
; Corrupts AF alone, IX and IY kept as in ALL_SEG.
m_fre_seg:
        push    hl
        push    de
        push    bc
        push    ix
        push    iy
        leg_sys SYS_SEGFREE
        pop     iy
        pop     ix
        pop     bc
        jr      c,.out
        ld      hl,leg_mapvar+2
        inc     (hl)
        inc     hl
        inc     hl
        dec     (hl)
        or      a
.out:   pop     de
        pop     hl
        ret

; RD_SEG — A = a segment, HL = an address in it: A = the byte. WR_SEG —
; the same with E written. Through page 2, put back from the shadow.
; Preserves BC, DE, HL.
m_rd_seg:
        push    hl
        push    bc
        ld      c,a
        set     7,h
        res     6,h
        di
        ld      a,c
        out     (0FEh),a
        ld      c,(hl)
        ld      a,(leg_segs+2)
        out     (0FEh),a
        ei
        ld      a,c
        pop     bc
        pop     hl
        ret
m_wr_seg:
        push    hl
        push    bc
        ld      c,a
        set     7,h
        res     6,h
        di
        ld      a,c
        out     (0FEh),a
        ld      (hl),e
        ld      a,(leg_segs+2)
        out     (0FEh),a
        ei
        pop     bc
        pop     hl
        ret

; CAL_SEG — IYh = a segment, IX = an address: the routine there called
; with AF, BC, DE, HL, the page's segment put back after. CALLS — the
; segment and the address follow the call. A page-3 address is called in
; place.
m_calls:
        ex      (sp),hl
        push    af
        ld      a,(hl)
        ld      iyh,a
        inc     hl
        ld      a,(hl)
        ld      ixl,a
        inc     hl
        ld      a,(hl)
        ld      ixh,a
        inc     hl
        pop     af
        ex      (sp),hl
m_cal_seg:
        ld      (ms_jp+1),ix
        ld      (ms_af),a
        ld      a,ixh
        rlca
        rlca
        and     3
        ld      (ms_page),a
        cp      3
        jr      z,.go
        push    hl
        push    de
        push    bc
        ld      e,a
        ld      d,0
        ld      hl,leg_segs
        add     hl,de
        ld      a,(hl)
        ld      (ms_was),a
        ld      a,iyh
        ld      (hl),a
        ld      a,e
        add     a,0FCh
        ld      c,a
        ld      a,iyh
        out     (c),a
        pop     bc
        pop     de
        pop     hl
.go:    ld      a,(ms_af)
        call    ms_jp
        ld      (ms_af),a
        ld      a,(ms_page)
        cp      3
        jr      z,.back
        push    hl
        push    de
        push    bc
        ld      e,a
        ld      d,0
        ld      hl,leg_segs
        add     hl,de
        ld      a,(ms_was)
        ld      (hl),a
        ld      c,e
        ld      a,c
        add     a,0FCh
        ld      c,a
        ld      a,(ms_was)
        out     (c),a
        pop     bc
        pop     de
        pop     hl
.back:  ld      a,(ms_af)
        ret
ms_jp:  jp      0

; PUT_PH — HL's page gets segment A; GET_PH — A = the segment in HL's
; page. PUT_Pn/GET_Pn the same for a named page; PUT_P3 does nothing,
; GET_P3 answers the legacy segment. PUT preserves everything; GET
; corrupts A alone.
m_put_ph:
        push    bc
        ld      b,a
        ld      a,h
        rlca
        rlca
        and     3
        cp      3
        jr      z,.p3
        push    hl
        push    de
        ld      e,a
        ld      d,0
        ld      hl,leg_segs
        add     hl,de
        ld      (hl),b
        ld      a,e
        add     a,0FCh
        ld      c,a
        out     (c),b
        pop     de
        pop     hl
.p3:    ld      a,b
        pop     bc
        ret
m_get_ph:
        push    hl
        push    de
        ld      a,h
        rlca
        rlca
        and     3
        cp      3
        jr      z,.p3
        ld      e,a
        ld      d,0
        ld      hl,leg_segs
        add     hl,de
        ld      a,(hl)
        pop     de
        pop     hl
        ret
.p3:    ld      a,(leg_seg3)
        pop     de
        pop     hl
        ret
m_put_p0:
        ld      (leg_segs+0),a
        out     (0FCh),a
        ret
m_put_p1:
        ld      (leg_segs+1),a
        out     (0FDh),a
        ret
m_put_p2:
        ld      (leg_segs+2),a
        out     (0FEh),a
        ret
m_put_p3:
        ret
m_get_p0:
        ld      a,(leg_segs+0)
        ret
m_get_p1:
        ld      a,(leg_segs+1)
        ret
m_get_p2:
        ld      a,(leg_segs+2)
        ret
m_get_p3:
        ld      a,(leg_seg3)
        ret

; leg_extbio — FFCAh: D = 4 is the mapper support — E = 1 the variable
; table (A = the slot, HL -> it), E = 2 the routines (A = segments, B =
; the slot, C = free, HL -> the jump table). Anything else comes back with
; every register as it was: the absent answer.
leg_extbio:
        push    af
        ld      a,d
        cp      4
        jr      nz,.no
        ld      a,e
        cp      1
        jr      z,.vars
        cp      2
        jr      z,.table
.no:    pop     af
        ret
.vars:  pop     af
        ld      a,(leg_mapvar+0)
        ld      hl,leg_mapvar
        ret
.table: pop     af
        ld      a,(leg_mapvar+0)
        ld      b,a
        ld      a,(leg_mapvar+2)
        ld      c,a
        ld      a,(leg_mapvar+1)
        ld      hl,leg_maptab
        ret

        include "leg/legh.asm"
        include "leg/legc.asm"

; ---------------------------------------------------------------------
; Variables

leg_usp:        dw 0            ; the program's SP during a BDOS call
leg_usp2:       dw 0            ; the layer's SP during a crossing
leg_defab:      dw 0            ; the abort routine, 0 = none
leg_lasterr:    db 0            ; the last error code
leg_code:       db 0            ; the termination code on its way out
bi_buf:         dw 0            ; _BUFIN's buffer
leg_left:       dw 0            ; the load: bytes still to read,
leg_addr:       dw 0            ;   where the next go
cs_page:        db 0            ; leg_rdslt/wrslt: the target's page,
cs_slot:        db 0            ;   the slot that was there
rs_val:         db 0            ; leg_rdslt/wrslt: the slot, then the byte
rs_dir:         db 0            ;   0 read, 1 write
ms_page:        db 0            ; CAL_SEG: the page, the segment that was
ms_was:         db 0            ;   there, A across the call
ms_af:          db 0
leg_code2:      db 0            ; the secondary code on the way out
leg_nest:       db 0            ; BDOS calls in progress
leg_hl:         dw 0            ; the dispatch: the program's HL,
leg_fn:         dw 0            ;   the handler
leg_sva8:       db 0            ; leg_ramin: the slots it found, primary
leg_svff:       db 0            ;   and secondary
leg_inb:        db 0            ; a call of the body's: bit 0 while one is
                                ;   in progress, bit 1 when the buffers a
                                ;   crossing names are the body's
leg_fnum:       db 0            ;   the function's number
leg_end:                                ; the image ends: what follows is
                                        ; not copied, and legf_init sets
                                        ; what must start known
; Page 3's variables outside the image: not emitted, not copied — the
; segment's bytes below the hinge, set by legf_init where they must start
; known. The same macro lays the body's out after its image, below.
    macro leg_bss Q1,Q2
Q1      equ     lbss_at
lbss_at  =       lbss_at+Q2
    endm
lbss_at  =       leg_end
        leg_bss leg_defer,2   ; the disk error routine, 0 = none
        leg_bss leg_xdrv,1   ; leg_xlate: the drive named, physical
        leg_bss leg_xwr,1   ; 1 while a call writes (for _DEFER)
        leg_bss leg_lpos,1   ; the console line: delivered so far,
        leg_bss leg_llen,1   ;   its length, 0 = none held
        leg_bss sa_a,1   ; leg_xsys: the arguments kept
        leg_bss sa_hl,2
        leg_bss sa_de,2
        leg_bss sa_bc,2
        leg_bss sa_n,1
        leg_bss leg_hand,LEG_NHAND*3   ; the handles
        leg_bss leg_fdrow,5*FR_SIZE   ; descriptors 3-7: where their files are
        leg_bss leg_fpos,LEG_NHAND*FP_SIZE ; an FCB row: the descriptor's
                                        ;   position as known, its stamp
        leg_bss leg_fstamp,1   ; the stamp counter (legc.asm)
        leg_bss leg_dta,2   ; the transfer address: the FCB record
                                        ;   functions', in page 3
        leg_bss fc_rown,1   ; a record function: the row's index,
        leg_bss fc_pos,4   ;   the record's position,
        leg_bss fc_len,2   ;   the bytes to move, the bytes moved
        leg_bss fc_got,2
        leg_bss fc_rsz,2   ;   a block function's record size,
        leg_bss fc_n,2   ;   its record count, the records moved,
        leg_bss fc_recs_n,2
        leg_bss fc_fcb,2   ;   the FCB's address, read or write,
        leg_bss fc_rw,1
        leg_bss fc_acc,4   ;   fc_mul's accumulator
        leg_bss leg_line,LEG_LINEMAX+4   ; _READ's console line, DOS 2's
                                        ;   buffer shape, CR LF after it
        leg_bss lb_six,64   ; the staging buffers (legb.asm): IX's file
        leg_bss lb_shl,LB_SHL   ;   info block, HL's argument, DE's — the
        leg_bss lb_sde,LB_SDE+1   ;   largest last, behind the others
        leg_bss leg_stack,LEG_STACK
leg_stack_top   equ lbss_at
        leg_bss leg_isp,2   ; leg_isr: the interrupted SP
        leg_bss leg_istack,LEG_ISTACK   ; and its own stack
leg_istack_top  equ lbss_at
leg_bss_end     equ lbss_at

;       ASSERT  leg_bss_end <= K_HINGE

; ---------------------------------------------------------------------
; The body: build/legb.bin, at LEG_BODY

        OUTPUT  "build/legb.bin"
        org     LEG_BODY
        include "leg/legb.asm"
        include "leg/legf.asm"
        include "leg/legk.asm"
; The entry (legi.asm), an overlay: the record and the environment store
; lie over its code once it has run.
leg_once:
        include "leg/legi.asm"
leg_once_end:
leg_rec         equ leg_once            ; DIRENT_SIZE: a short record
leg_env         equ leg_rec+DIRENT_SIZE ; LEG_ENVMAX: the environment,
                                        ;   "NAME=value",0 pairs, then 0
leg_path        equ leg_env+LEG_ENVMAX  ; LEG_PATHMAX: a translated path,
                                        ;   written by the file functions
                                        ;   alone, never at the launch
s_fcbext        equ leg_path+LEG_PATHMAX ; the FCB searches' extent (legk.asm)
fb_victim       equ s_fcbext+1          ; the last FCB row taken back
        ASSERT  fb_victim+1 <= leg_once_end
        ASSERT  leg_rec+DIRENT_SIZE <= legf_init   ; over leg_entry alone
legb_end:                               ; the body's image ends
lbss_at  =       legb_end
        leg_bss leg_dcwd,16   ; each physical drive's directory cluster
        leg_bss leg_assign,8   ; logical -> physical drive, 1 = A:
        leg_bss leg_login,1   ; the login vector
        leg_bss leg_curp,1   ; the current drive, physical
        leg_bss leg_level,1   ; the _FORK level
        leg_bss leg_vfy,1   ; the verify flag
        leg_bss leg_chk,1   ; the disk check flag
        leg_bss leg_xlog,1   ; leg_xlate: the drive named, logical
        leg_bss leg_xback,1   ;   1: the kernel's directory was moved
        leg_bss leg_xslash,1   ;   1: the path ended in a \
        leg_bss leg_xbuf,2   ; leg_xlate: where the path goes
        leg_bss leg_xcur,2   ; the directory entered: its cluster
        leg_bss leg_loc,3   ; a locator for chdir
        leg_bss leg_wpos,2   ; the whole path's last item
        leg_bss o_mode,1   ; _OPEN, _CREATE: the mode, the
        leg_bss o_attr,1   ;   attributes, the handle's flags, the
        leg_bss o_hflags,1   ;   descriptor
        leg_bss o_fd,1
        leg_bss hx_fd,1   ; a handle function: the descriptor,
        leg_bss hx_row,2   ;   the handle's row,
        leg_bss hx_new,1   ;   the one that replaces it,
        leg_bss hx_pos,4   ;   its position across the two
        leg_bss x_mvclus,2   ; _MOVE: the destination's cluster
        leg_bss s_fib,2   ; the search's FIB
        leg_bss s_fd,1   ;   its descriptor
        leg_bss s_attr,1   ;   the attributes wanted
        leg_bss s_name11,11   ; an eleven-byte name
        leg_bss s_new11,11   ; _RENAME's new one
        leg_bss s_tmpl11,11   ; _FNEW's template
        leg_bss s_fcbfib,FI_LOG+1   ; the FCB searches' own FIB (legk.asm):
                                        ;   what leg_find and leg_fibfill touch
        leg_bss ex_n,1   ; leg_exp11: a byte stored
        leg_bss p_drv,1   ; _PARSE: the drive
        leg_bss leg_name,LEG_NAMEMAX   ; a path's last item
        leg_bss leg_path2,LEG_PATHMAX   ; a second one
        leg_bss leg_wpath,64   ; the whole path of the last find
        leg_bss leg_sf,SF_SIZE   ; a statfs block
        leg_bss lb_d,1   ; the door (legb.asm): the call's descriptor,
        leg_bss lb_b,1   ;   the program's B,
        leg_bss lb_hl,2   ;   its HL and DE, its IX,
        leg_bss lb_de,2
        leg_bss lb_ix,2
        leg_bss lb_st,1   ;   what was staged: bit 0 DE, 1 HL, 2 IX
        leg_bss lb_rhl,2   ;   the handler's HL and BC on the way out
        leg_bss lb_rbc,2
legb_bss_end    equ lbss_at
; An FCB name function's variables (legk.asm) lie over those of the
; handle, move and template functions, which no FCB function reaches;
; _EXPLAIN's descriptor over the search's.
fb_fcb          equ hx_pos              ; 2: the FCB's address,
fb_omode        equ hx_pos+2            ;   the open mode,
fb_any          equ hx_pos+3            ;   whether a walk did anything,
fb_rown         equ hx_new              ;   the row taken,
fb_each         equ x_mvclus            ; 2: a walk's routine
s_new11f        equ s_tmpl11            ; 11: _FREN's new name
x_fd            equ s_fd                ; _EXPLAIN: /bin/dos

;       ASSERT  legb_bss_end <= LEG_BODY+LEG_BMAX

; What is left: below the hinge in page 3, and of the buffers lent to the
; body (make sizes prints both).
LEG_ROOM        equ K_HINGE-leg_bss_end
LEGB_ROOM       equ LEG_BODY+LEG_BMAX-legb_bss_end
        EXPORT  LEG_ROOM
        EXPORT  LEGB_ROOM
; Where a crossing comes back to in leg_xsys: the legacy test's harness
; plants a disk error there to reach the program's error routine, which
; no emulated disk will produce.
LEG_T_XSYS      equ leg_xsys.tback
        EXPORT  LEG_T_XSYS
