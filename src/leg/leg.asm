; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer: what a .COM program finds above its TPA. Assembled at
; LEG_BASE into build/leg.bin and carried inside /bin/dos, which hands it
; to dosexec; the kernel copies it into the legacy page 3 — a segment of
; the program's own that page 3 shows while it runs — beside a copy of the
; kernel's page 3 from K_HINGE up (the drivers' work areas, Nextor's fixed
; area, the BIOS work area), and enters it once.
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

; MSX-DOS 2 error codes the layer returns (DOS2-PIS §6).
D_STOP          equ 9Fh         ; Ctrl-STOP pressed
D_CTRLC         equ 9Eh         ; Ctrl-C pressed
D_ABORT         equ 9Dh         ; Disk operation aborted
D_IBDOS         equ 0DCh        ; Invalid MSX-DOS call
D_ISBFN         equ 0B8h        ; Invalid sub-function number
D_IPARM         equ 8Bh         ; Invalid parameter
D_INTER         equ 0DFh        ; Internal error
D_NORAM         equ 0DEh        ; Not enough memory
D_IDRV          equ 0DBh        ; Invalid drive
D_IFNM          equ 0DAh        ; Invalid filename
D_IPATH         equ 0D9h        ; Invalid pathname
D_PLONG         equ 0D8h        ; Pathname too long
D_NOFIL         equ 0D7h        ; File not found
D_NODIR         equ 0D6h        ; Directory not found
D_DRFUL         equ 0D5h        ; Root directory full
D_DKFUL         equ 0D4h        ; Disk full
D_DUPF          equ 0D3h        ; Duplicate filename
D_DIRE          equ 0D2h        ; Invalid directory move
D_FILRO         equ 0D1h        ; Read only file
D_DIRNE         equ 0D0h        ; Directory not empty
D_IATTR         equ 0CFh        ; Invalid attributes
D_DOT           equ 0CEh        ; Invalid . or .. operation
D_SYSX          equ 0CDh        ; System file exists
D_DIRX          equ 0CCh        ; Directory exists
D_FILEX         equ 0CBh        ; File exists
D_FOPEN         equ 0CAh        ; File already in use
D_EOF           equ 0C7h        ; End of file
D_ACCV          equ 0C6h        ; File access violation
D_IPROC         equ 0C5h        ; Invalid process id
D_NHAND         equ 0C4h        ; No spare file handles
D_IHAND         equ 0C3h        ; Invalid file handle
D_IDEV          equ 0C1h        ; Invalid device operation
D_IENV          equ 0C0h        ; Invalid environment string
D_ELONG         equ 0BFh        ; Environment string too long
D_HDEAD         equ 0BAh        ; File handle has been deleted
D_DISK          equ 0FDh        ; Disk error
D_WPROT         equ 0F8h        ; Write protected disk

LEG_STACK       equ 192         ; the layer's own stack for a BDOS call
; The handle table (legf.asm): LEG_NHAND rows of three bytes.
LEG_NHAND       equ 16
HN_FD            equ 0           ; a descriptor 3-7, a device HD_*, or free
HN_FLAGS         equ 1           ; HF_*
HN_LEVEL         equ 2           ; the _FORK level it was opened at
HF_NOWR         equ 1           ; no writes — the open mode's own bits
HF_NORD         equ 2           ; no reads
HF_INH          equ 4           ; inheritable
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

        org     LEG_BASE
        db      0,16h,0,0,0,0           ; CP/M 2.2's version and serial
        jp      leg_bdos                ; LEG_BDOS: the TPA's top
        block   LEG_VEC-$
        jp      leg_entry               ; +0: from dosexec, once
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

; leg_go — the end of the entry, outside the overlay the entry's code
; becomes: the stack where MSX-DOS puts it with WBOOT under it so that a
; ret ends the program, the environment store emptied — it lies over the
; entry's code, which has run — and into the program with interrupts
; enabled.
leg_go: xor     a
        ld      (leg_env),a
        ld      hl,LEG_BIOS             ; a ret from the program is WBOOT
        push    hl
        ld      hl,0
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
; is; the crossing runs on the hinge's. Returns with interrupts enabled,
; the result in HL and AF (CF and the errno as the syscall left them).
leg_syscall:
        di
        ld      (leg_usp2),sp
        ld      sp,K_HINGE_SP
        ld      ix,(leg_segs)           ; IXL = page 0, IXH = page 1
        ld      iy,(leg_segs+1)         ; IYH = page 2
        ex      af,af'                  ; the stub uses A
        jp      K_HINGE
leg_ret:                                ; from the second stub, di, AF in AF'
        ld      a,(leg_started)
        or      a
        jp      z,leg_entry
        ld      sp,(leg_usp2)
        ex      af,af'
        ei
        ret

; leg_term — A = the termination code: the abort routine, if the program
; defined one (DE = its address, _DEFAB), with A = the code and B = the
; error that caused it, then the crossing that ends the process with the
; code as its status. Never returns.
leg_term:
        ld      b,0
leg_term2:                              ; B = the error that caused it
        ld      (leg_code),a
        ld      a,b
        ld      (leg_code2),a
        ld      hl,(leg_defab)
        ld      a,h
        or      l
        jr      z,.go
        ld      a,(leg_code)
        ld      b,0
        ld      de,.go
        push    de
        ld      a,(leg_code2)
        ld      b,a
        ld      a,(leg_code)
        jp      (hl)
.go:    di
        ld      a,(leg_code)
        ld      sp,K_HINGE_SP
        exx
        ld      c,LEG_EXIT
        exx
        ex      af,af'
        jp      K_HINGE

; leg_wboot — jp 0, a ret from the program, the BIOS table's WBOOT.
leg_wboot:
        xor     a
        jp      leg_term

; leg_abort — A = D_STOP or D_CTRLC: the program ends with it, as
; MSX-DOS ends one whose console function met the key.
leg_abort:
        ld      (leg_lasterr),a
        jp      leg_term

; ---------------------------------------------------------------------
; The BDOS

; leg_bdos — CALL 0005h: C = the function. The program's SP kept, the
; layer's stack taken, IX and IY preserved as the specification promises.
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
        pop     af
        ld      hl,.done
        push    hl                      ; where the handler returns
        ld      hl,(leg_hl)
        push    hl
        ld      hl,(leg_fn)
        ex      (sp),hl                 ; the handler under it, HL the program's
        ret                             ; into the handler
.done:  pop     iy
        pop     ix
        push    hl                      ; the result
        ld      hl,leg_nest
        dec     (hl)
        pop     hl
        jr      nz,.ret
        ld      sp,(leg_usp)
.ret:   ei
        ret
.isbfn: pop     af
        ld      a,D_IBDOS
        ld      (leg_lasterr),a
        ld      l,a
        ld      h,0
        ld      b,h
        jr      .done

leg_tab_lo:                             ; 00h-31h
        dw      f_term0, f_conin, f_conout, f_ibdos, f_ibdos, f_ibdos
        dw      f_dirio, f_dirin, f_innoe, f_strout, f_bufin, f_const
        dw      f_cpmver, f_dskrst, f_seldsk
        dw      f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos
        dw      f_ibdos, f_ibdos, f_ibdos   ; 0Fh-17h: FCBs
        dw      f_login, f_curdrv, f_setdta, f_alloc
        dw      f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos ; 1Ch-20h
        dw      f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos, f_ibdos
        dw      f_ibdos, f_ibdos, f_ibdos   ; 21h-29h: FCBs
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

; _EXPLAIN (66h): B = an error code, DE -> a 64-byte buffer: its message,
; 0-terminated — "Error nnH" for a code the layer does not know.
f_explain:
        ld      hl,leg_msgs
.find:  ld      a,(hl)
        or      a
        jr      z,.hex
        cp      b
        inc     hl
        jr      z,.copy
.skip:  ld      a,(hl)
        inc     hl
        or      a
        jr      nz,.skip
        jr      .find
.copy:  ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.copy
        xor     a
        ret
.hex:   ld      hl,s_error
.hexc:  ld      a,(hl)
        or      a
        jr      z,.digits
        ld      (de),a
        inc     hl
        inc     de
        jr      .hexc
.digits:
        ld      a,b
        rrca
        rrca
        rrca
        rrca
        call    .nib
        ld      a,b
        call    .nib
        ld      a,'H'
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        ret
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,.put
        add     a,'A'-'9'-1
.put:   ld      (de),a
        inc     de
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
; is kept in memory across the call — the page and the slot ride in IY —
; because the interrupt trampoline comes through here too, and a tick
; inside a CALSLT must not rewrite the one in progress.
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
        push    hl
        ld      hl,.back
        ex      (sp),hl                 ; .back pushed, hl as it was
        jp      (ix)
.back:  push    af
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
leg_isr:
        di
        push    af
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
        ei
        reti

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

; ALL_SEG — A = 0 (user) or 1 (system), B = 0 (the primary mapper) or
; F0h + slot: A = the segment, B = its mapper's slot; CF when none is
; free. Every segment is the program's and goes at its exit. Corrupts
; AF, BC.
m_all_seg:
        push    hl
        push    de
        leg_sys SYS_SEGALLOC
        jr      c,.none
        ld      a,l
        ld      hl,leg_mapvar+2
        dec     (hl)
        inc     hl
        inc     hl
        inc     (hl)
        ld      b,0
        or      a
.out:   pop     de
        pop     hl
        ret
.none:  scf
        jr      .out

; FRE_SEG — A = a segment: freed; CF when it is not the program's.
m_fre_seg:
        push    hl
        push    de
        leg_sys SYS_SEGFREE
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

        include "leg/legf.asm"

; ---------------------------------------------------------------------
; Messages, variables

leg_msgs:
        db      D_STOP,"Ctrl-STOP pressed",0
        db      D_CTRLC,"Ctrl-C pressed",0
        db      D_ABORT,"Disk operation aborted",0
        db      D_IBDOS,"Invalid MSX-DOS call",0
        db      D_ISBFN,"Invalid sub-function number",0
        db      D_IPARM,"Invalid parameter",0
        db      D_INTER,"Internal error",0
        db      D_NORAM,"Not enough memory",0
        db      D_IDRV,"Invalid drive",0
        db      D_IFNM,"Invalid filename",0
        db      D_IPATH,"Invalid pathname",0
        db      D_PLONG,"Pathname too long",0
        db      D_NOFIL,"File not found",0
        db      D_NODIR,"Directory not found",0
        db      D_DRFUL,"Root directory full",0
        db      D_DKFUL,"Disk full",0
        db      D_DUPF,"Duplicate filename",0
        db      D_DIRE,"Invalid directory move",0
        db      D_FILRO,"Read only file",0
        db      D_DIRNE,"Directory not empty",0
        db      D_IATTR,"Invalid attributes",0
        db      D_DOT,"Invalid . or .. operation",0
        db      D_SYSX,"System file exists",0
        db      D_DIRX,"Directory exists",0
        db      D_FILEX,"File exists",0
        db      D_FOPEN,"File already in use",0
        db      D_EOF,"End of file",0
        db      D_ACCV,"File access violation",0
        db      D_IPROC,"Invalid process id",0
        db      D_NHAND,"No spare file handles",0
        db      D_IHAND,"Invalid file handle",0
        db      D_IDEV,"Invalid device operation",0
        db      D_IENV,"Invalid environment string",0
        db      D_ELONG,"Environment string too long",0
        db      D_HDEAD,"File handle has been deleted",0
        db      D_DISK,"Disk error",0
        db      D_WPROT,"Write protected disk",0
        db      0
s_error:        db "Error ",0

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
; The entry (legi.asm), an overlay: the record, the environment store and
; the console line lie over its code once it has run.
leg_once:
        include "leg/legi.asm"
leg_once_end:
leg_rec         equ leg_once            ; DIRENT_SIZE: a short record
leg_env         equ leg_rec+DIRENT_SIZE ; LEG_ENVMAX: the environment,
                                        ;   "NAME=value",0 pairs, then 0
leg_line        equ leg_env+LEG_ENVMAX  ; LEG_LINEMAX+4: _READ's console
                                        ;   line, DOS 2's buffer shape, CR
                                        ;   LF after it
        ASSERT  leg_line+LEG_LINEMAX+4 <= leg_once_end
        ASSERT  leg_rec+DIRENT_SIZE <= legf_init   ; over leg_entry alone
leg_end:                                ; the image ends: what follows is
                                        ; not copied, and legf_init sets
                                        ; what must start known
; The files' variables (legf.asm), outside the image: not emitted, not
; copied — the segment's bytes below the hinge, set by legf_init where
; they must start known.
    macro leg_bss Q1,Q2
Q1      equ     lbss_at
lbss_at  =       lbss_at+Q2
    endm
lbss_at  =       leg_end
        leg_bss leg_dcwd,16   ; each physical drive's directory cluster
        leg_bss leg_assign,8   ; logical -> physical drive, 1 = A:
        leg_bss leg_login,1   ; the login vector
        leg_bss leg_curp,1   ; the current drive, physical
        leg_bss leg_level,1   ; the _FORK level
        leg_bss leg_defer,2   ; the disk error routine, 0 = none
        leg_bss leg_dta,2   ; the transfer address (5.3's FCBs)
        leg_bss leg_vfy,1   ; the verify flag
        leg_bss leg_chk,1   ; the disk check flag
        leg_bss leg_xdrv,1   ; leg_xlate: the drive named, physical,
        leg_bss leg_xlog,1   ;   and logical
        leg_bss leg_xback,1   ;   1: the kernel's directory was moved
        leg_bss leg_xslash,1   ;   1: the path ended in a \
        leg_bss leg_xwr,1   ; 1 while a call writes (for _DEFER)
        leg_bss leg_xbuf,2   ; leg_xlate: where the path goes
        leg_bss leg_xcur,2   ; the directory entered: its cluster
        leg_bss leg_loc,3   ; a locator for chdir
        leg_bss leg_wpos,2   ; the whole path's last item
        leg_bss leg_lpos,1   ; the console line: delivered so far,
        leg_bss leg_llen,1   ;   its length, 0 = none held
        leg_bss sa_a,1   ; leg_xsys: the arguments kept
        leg_bss sa_hl,2
        leg_bss sa_de,2
        leg_bss sa_bc,2
        leg_bss sa_n,1
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
        leg_bss ex_n,1   ; leg_exp11: a byte stored
        leg_bss p_drv,1   ; _PARSE: the drive
        leg_bss leg_name,LEG_NAMEMAX   ; a path's last item
        leg_bss leg_hand,LEG_NHAND*3   ; the handles
        leg_bss leg_fdrow,5*FR_SIZE   ; descriptors 3-7: where their files are
        leg_bss leg_path,LEG_PATHMAX   ; a translated path
        leg_bss leg_path2,LEG_PATHMAX   ; a second one
        leg_bss leg_wpath,64   ; the whole path of the last find
        leg_bss leg_sf,SF_SIZE   ; a statfs block
        leg_bss leg_stack,LEG_STACK
leg_stack_top   equ lbss_at
leg_bss_end     equ lbss_at

        ASSERT  leg_bss_end <= K_HINGE
