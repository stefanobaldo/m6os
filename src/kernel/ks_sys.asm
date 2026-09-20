; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The cold syscalls, in the switched part: procinfo, segalloc, segfree,
; segmap, kill, signal, dosenter, ttymode and ttyline, each run once per
; command, per program, per prompt or per ps row, none blocking, none
; touching page 2 — entered through k_sw_s like the filesystem's, so the
; storage segment is in page 1 and a process's memory is reached through
; um_in and um_out (ks_vfs.asm). And the exit check of an MSX-DOS
; program's process, ks_dos_check, called by sys_exit through the window.
; What they need of the resident beyond the header — the allocator's
; owner byte, the signal machinery, the console's and the keyboard's
; set-up, the cursor, dosenter's last step — comes through K_API2; the
; resident objects they write — the line's state, the console's cursor,
; the keyboard's baseline, the hinge's template — through the addresses
; the header keeps for them (K_LDSTATE and the three beside it).

; ks_procinfo — SYS_PROCINFO: A = pid, HL = a PROCINFO_SIZE buffer: the
; process's row, then its extension row, copied as they are — the
; kernel's own layout, which ps follows and nothing else should. E_INVAL
; past NPROC, E_SRCH for a free row, E_FAULT for a buffer reaching page 3
; (process 0's may be anywhere). The rows are gathered in VV_PATH, free
; here, and go out through um_out, whichever page the buffer is in.
ks_procinfo:
        cp      NPROC
        jr      nc,.inval
        ld      e,a                     ; e = the pid
        ld      bc,PROCINFO_SIZE
        call    um_check                ; the buffer, before a byte moves
        ret     c                       ; E_FAULT
        ld      a,e
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        push    hl                      ; the buffer
        push    de                      ; e = the pid
        ld      l,a
        ld      h,high K_PROC
        ld      a,(hl)
        or      a                       ; PS_FREE
        jr      z,.srch
        ld      de,SG+VV_PATH
        ld      bc,P_SIZE
        ldir                            ; the row, then the extension row
        pop     hl
        ld      a,l
        k_call2 API2_PX_ROW             ; hl -> it
        ld      bc,PX_SIZE
        ldir
        call    vfs_begin               ; the caller's pages, for um_out
        pop     de                      ; the buffer
        ld      hl,VV_PATH
        ld      bc,PROCINFO_SIZE
        call    um_out
        xor     a                       ; CF clear
        ret
.srch:  pop     de
        pop     hl
        ld      a,E_SRCH
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_segalloc — SYS_SEGALLOC: a segment for the caller, owner its pid,
; freed with everything else at its exit. Out: HL = A = the segment.
; E_NOMEM; E_PERM from process 0, whose segments nobody frees.
ks_segalloc:
        ld      a,(K_PID)
        or      a
        jr      z,.perm
        ld      b,a
        k_call  API_MEM_ALLOC
        jr      c,.nomem
        ld      l,a
        ld      h,0
        or      a
        ret
.nomem: ld      a,E_NOMEM
        scf
        ret
.perm:  ld      a,E_PERM
        scf
        ret

; ks_segfree — SYS_SEGFREE: A = a segment: freed, when it is the caller's
; and not one of its pages. E_INVAL otherwise. Out: HL = 0.
ks_segfree:
        ld      hl,(K_CUR)
        ld      de,P_SEG
        add     hl,de
        cp      (hl)
        jr      z,.inval
        inc     hl
        cp      (hl)
        jr      z,.inval
        inc     hl
        cp      (hl)
        jr      z,.inval
        ld      hl,K_PID
        ld      b,(hl)
        k_call  API_MEM_FREE
        jr      c,.inval
        ld      hl,0
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_segmap — SYS_SEGMAP: A = a page, 1 or 2; B = a segment the caller
; owns. It becomes the process's page — P_SEG and K_MAP here, the mapper
; at the gate's return, which maps both pages from K_MAP — so that the
; gate and the scheduler keep it there. E_INVAL for another page or
; another owner. Out: HL = 0.
ks_segmap:
        dec     a
        cp      2
        jr      nc,.inval               ; page 0 or 3
        inc     a
        ld      c,a                     ; the page
        ld      a,b
        k_call2 API2_MEM_OWNER          ; a = the segment's owner
        ld      hl,K_PID
        cp      (hl)
        jr      nz,.inval
        ld      hl,(K_CUR)
        ld      de,P_SEG
        add     hl,de
        ld      e,c
        ld      d,0
        add     hl,de
        ld      (hl),b
        ld      hl,K_MAP
        add     hl,de
        ld      (hl),b
        ld      hl,0
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_kill — SYS_KILL: A = pid, B = a signal. The process named ends with
; 128 + the signal, unless it ignores it; a zombie or an ignoring process
; is success with no effect. EPERM for pid 0, EINVAL for a pid past the
; table or a signal that is none of the four, ESRCH for a free row. A
; process killing itself goes through sig_send like any other — which
; leaves the signal owed on it — and then straight into sig_stub, which
; never returns: sys_exit takes the stack and the scheduler the pages.
ks_kill:
        or      a
        jr      z,.perm
        cp      NPROC
        jr      nc,.inval
        ld      c,a                     ; c = the pid
        ld      a,b
        cp      SIGKILL
        jr      z,.sigok
        k_call2 API2_SIG_BIT
        jr      c,.inval
.sigok: ld      a,c
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,high K_PROC           ; hl -> the row
        ld      a,(hl)
        or      a
        jr      z,.srch                 ; PS_FREE
        ld      a,(K_PID)
        cp      c                       ; Z: myself
        push    af
        ld      c,b                     ; c = the signal
        di
        k_call2 API2_SIG_SEND           ; a = 1 if it was taken
        ei
        ld      c,a
        pop     af
        ld      a,c
        jr      nz,.ok                  ; another process: done
        or      a
        jr      z,.ok                   ; myself, ignored
        k_call2 API2_SIG_STUB           ; myself, and not ignored: die now
.ok:    or      a                       ; CF clear
        ret
.perm:  ld      a,E_PERM
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.srch:  ld      a,E_SRCH
        scf
        ret

; ks_signal — SYS_SIGNAL: A = a signal, B = SIG_DFL or SIG_IGN. Out: L =
; the action that was. EINVAL for SIGKILL or a number that is none of the
; other three. The mask is inherited by a child and kept across exec.
ks_signal:
        k_call2 API2_SIG_BIT
        jr      c,.inval
        ld      c,a                     ; c = the bit
        ld      a,(K_PID)
        k_call2 API2_PX_ROW
        ld      de,PX_SIGIGN
        add     hl,de                   ; hl -> PX_SIGIGN
        ld      a,(hl)
        and     c
        ld      e,SIG_DFL
        jr      z,.was
        ld      e,SIG_IGN
.was:   ld      a,b
        or      a
        jr      z,.clear
        ld      a,(hl)
        or      c
        ld      (hl),a
        jr      .done
.clear: ld      a,c
        cpl
        and     (hl)
        ld      (hl),a
.done:  ld      l,e
        ld      h,0
        xor     a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_dos_check — KS_DOS_CHECK: the first thing sys_exit does, through the
; window, on the syscall stack, with interrupts as they were: nothing
; unless the dying process is the legacy one. Then: the process's
; original page 0 back in page 0, so that the interrupt vector is there
; whatever the program mapped; the PSG silenced; the console up again,
; keeping the screen and the cursor when the program left SCREEN 0 at 80
; columns and clearing it otherwise — read from the BIOS variables in the
; legacy copy, through page 1, since page 2 is this code; the buffers the
; cache lent to the layer's body (ks_dosenter) returned, free, through
; page 1 too; the keyboard's baseline taken from the matrix as it is, so
; a key still held does not register; K_DOSPID cleared. Preserves A (the
; status).
ks_dos_check:
        push    af
        ld      hl,K_DOSPID
        ld      a,(K_PID)
        cp      (hl)
        jp      nz,.out
        ld      (hl),0
        di
        ld      a,(K_DOSP0)
        ld      (K_MAP+0),a
        out     (0FCh),a
        ei
        ld      a,8                     ; PSG channels A, B, C silent
        call    .psg0
        ld      a,9
        call    .psg0
        ld      a,10
        call    .psg0
        di
        ld      a,(K_REC+KR_SEG64K+2)   ; the storage segment, into page 1:
        out     (0FDh),a                ;   the buffers dosenter lent to the
        ld      ix,SG+ST_HDR            ;   layer's body are the cache's
        ld      b,BUF_N                 ;   again, free
        ld      de,H_SIZE
.back:  ld      a,(ix+H_VOL)
        cp      VOL_LENT
        jr      nz,.keep
        ld      (ix+H_VOL),VOL_NONE
        ld      (ix+H_FLAGS),0
.keep:  add     ix,de
        djnz    .back
        ld      a,(K_HINGE2+1)          ; the legacy segment, into page 1
        out     (0FDh),a
        ld      a,(B_SCRMOD-8000h)
        ld      b,a
        ld      a,(B_LINLEN-8000h)
        ld      c,a
        ld      hl,(B_CSRY-8000h)       ; l = the row, h = the column
        ld      a,(K_MAP+1)             ; the process's page 1 back
        out     (0FDh),a
        ei
        push    hl
        push    bc
        k_call2 API2_CON_INIT
        pop     bc
        pop     hl
        ld      iy,(K_CONCUR)           ; iy -> con_row, con_col after it
        ld      a,b                     ; the screen mode
        or      a
        jr      nz,.clear
        ld      a,c                     ; the columns
        cp      CON_COLS
        jr      nz,.clear
        ld      a,l
        dec     a
        cp      CON_ROWS
        jr      c,.row
        ld      a,CON_ROWS-1
.row:   ld      (iy+0),a                ; con_row
        ld      a,h
        dec     a
        cp      CON_COLS
        jr      c,.col
        xor     a
.col:   ld      (iy+1),a                ; con_col
        jr      .kbd
.clear: xor     a
        ld      b,CON_ROWS
        k_call2 API2_VDP_CLEAR_ROWS
        ld      iy,(K_CONCUR)
        xor     a
        ld      (iy+0),a
        ld      (iy+1),a
.kbd:   k_call2 API2_KBD_INIT
        ld      hl,(K_KBDLAST)          ; hl -> kbd_last: the matrix as it is
        ld      b,11                    ; now is the scan's baseline: a key
        ld      c,0                     ; still held — the RET that ended the
.row2:  in      a,(PPI_C)               ; program — is not a new press
        and     0F0h
        or      c
        out     (PPI_C),a
        in      a,(PPI_B)
        ld      (hl),a
        inc     hl
        inc     c
        djnz    .row2
.out:   pop     af
        ret
.psg0:  out     (0A0h),a
        xor     a
        out     (0A1h),a
        ret

; dosenter's ways out with an error, before it: within a jr of every check.
kde_perm:
        ld      a,E_PERM
        jr      kde_err3
kde_busy:
        ld      a,E_BUSY
        jr      kde_err3
kde_inval3:
        ld      a,E_INVAL
kde_err3:
        pop     de                      ; where, the length, the body
        pop     bc
        pop     hl
        scf
        ret
kde_fault:
        ld      a,E_FAULT
        scf
        ret
kde_inval:
        ld      a,E_INVAL
        scf
        ret

; ks_dosenter — SYS_DOSENTER: A = the legacy page-3 segment, the
; caller's, filled by the caller as the layer expects; the caller's pages
; 1 and 2 hold the program's through segmap; HL = the layer's body in the
; caller's page 0, BC = its length and DE = where in the storage segment
; it goes, or BC = 0 for none. The body takes the place of the block
; cache's buffers from DE to the segment's end, lent until ks_dos_check
; returns them: their headers marked VOL_LENT and HF_LENT, which nothing
; finds, evicts or flushes; none is dirty, since nothing is between
; syscalls. DE is a buffer's start with BUF_MIN buffers left below it, and
; the body ends within the segment; the layer maps the segment for a file
; function and finds its body there. Every check comes before the first
; write. Then the hinge into this page
; and into the legacy copy — through page 1, since page 2 is this code —
; the BIOS's cursor and the storage segment's number in that copy, the
; row marked, and the second stub taken by dos_tail, the resident step
; that closes the window this code runs in. Never returns on success.
; E_PERM (process 0), E_BUSY (a legacy process exists), E_INVAL (a segment
; not the caller's; a place for the body that is not a buffer's start,
; leaves the cache under BUF_MIN, or does not hold it), E_FAULT (a body
; not wholly in page 0).
ks_dosenter:
        push    hl                      ; the body
        push    bc                      ; its length
        push    de                      ; where it goes
        ld      c,a                     ; c = the legacy segment
        ld      a,(K_PID)
        or      a
        jr      z,kde_perm
        ld      b,a                     ; b = the pid
        ld      a,(K_DOSPID)
        or      a
        jr      nz,kde_busy
        ld      a,c
        k_call2 API2_MEM_OWNER          ; a = the segment's owner
        cp      b
        jr      nz,kde_inval3
        ld      (SG+SV_DOSARG),bc
        pop     de                      ; de = where
        pop     bc                      ; bc = the length
        pop     hl                      ; hl = the body
        ld      a,b
        or      c
        jr      z,.nobody
        push    hl
        add     hl,bc                   ; the body's end: 4000h at most
        dec     hl
        ld      a,h
        pop     hl
        jr      c,kde_fault
        cp      40h
        jr      nc,kde_fault
        ld      a,e                     ; where: a buffer's start,
        or      a
        jr      nz,kde_inval
        ld      a,d
        sub     high ST_BUF
        jr      c,kde_inval
        rra                             ; a = the buffer, CF = not its start
        jr      c,kde_inval
        cp      BUF_MIN                 ; BUF_MIN left to the cache,
        jr      c,kde_inval
        cp      BUF_N
        jr      nc,kde_inval
        push    hl
        ld      h,d
        ld      l,e
        add     hl,bc                   ; and the body within the segment
        dec     hl
        bit     6,h
        pop     hl
        jr      nz,kde_inval
        push    bc
        push    hl
        push    de
        ld      l,a                     ; the first lent buffer's header
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,SG+ST_HDR
        add     hl,de
        neg
        add     a,BUF_N
        ld      b,a                     ; buffers lent
        ld      de,H_FLAGS
.lend:  ld      (hl),VOL_LENT
        add     hl,de
        ld      (hl),HF_LENT
        inc     hl
        inc     hl                      ; H_SIZE = H_FLAGS + 2
        djnz    .lend
        pop     hl                      ; where, as this code sees it
        ld      de,SG
        add     hl,de
        ex      de,hl
        pop     hl
        pop     bc
        ldir
.nobody:
        ld      bc,(SG+SV_DOSARG)       ; c = the segment, b = the pid
        push    bc
        ; The hinge into this page: the template, its two segments patched.
        ld      hl,(K_DOSTMPL)
        ld      de,K_HINGE
        ld      bc,K_HINGE_STUBS
        ldir
        ld      a,(K_MAP+3)
        ld      (K_HINGE+1),a           ; this page's segment
        pop     bc
        ld      a,c
        ld      (K_HINGE2+1),a          ; the legacy segment
        ; Into the legacy copy, through page 1, with the cursor. Interrupts
        ; stay off from here to the crossing, as the hinge wants them.
        k_call2 API2_CON_CURSOR         ; l = the row, h = the column
        di
        ld      a,c
        out     (0FDh),a
        push    hl
        ld      hl,K_HINGE
        ld      de,K_HINGE-8000h
        ld      bc,K_HINGE_STUBS
        ldir
        pop     hl
        ld      a,l
        inc     a
        ld      (B_CSRY-8000h),a
        ld      a,h
        inc     a
        ld      (B_CSRX-8000h),a
        ld      a,(K_REC+KR_SEG64K+2)   ; where the body is, for the layer
        ld      (LEG_STSEG-8000h),a
        ; The row: three pages, its page 0 remembered, SIGINT ignored.
        ld      hl,(K_CUR)
        ld      de,P_NPAGES
        add     hl,de
        ld      (hl),3
        inc     hl
        ld      a,(hl)
        ld      (K_DOSP0),a
        ld      a,(K_PID)
        ld      (K_DOSPID),a
        k_call2 API2_PX_ROW
        ld      de,PX_SIGIGN
        add     hl,de
        set     0,(hl)                  ; SIGIGN_INT
        k_call2 API2_DOS_TAIL           ; the pages back, and across

; ks_ttymode — SYS_TTYMODE: A = TTY_CANON, TTY_RAW or TTY_RECALL. Out:
; L = the mode that was. EINVAL for anything else. The mode is the
; terminal's; a line delivered in part stays in the buffer across a
; switch, an open line is dropped.
ks_ttymode:
        cp      TTY_RECALL+1
        jr      nc,.inval
        ld      ix,(K_LDSTATE)
        ld      l,(ix+LD_MODE)
        ld      h,0
        ld      (ix+LD_MODE),a
        ld      a,(ix+LD_OPEN)
        or      a
        jr      z,.set
        xor     a
        ld      (ix+LD_OPEN),a
        ld      (ix+LD_LEN),a
        ld      (ix+LD_POS),a
.set:   xor     a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_ttyline — SYS_TTYLINE: HL = a line, BC = its length, 0 to
; TTY_LINE-1. The open line replaced by it, or one opened at the cursor:
; the old line's cells blanked, the bytes copied, echoed, the cursor at
; their end. EINVAL for a longer one, EFAULT for a buffer reaching page 3
; (process 0's may be anywhere), both before anything is touched. The
; bytes come in through um_in, whichever page they are in, and land in
; the line between two calls into the editor. Corrupts everything.
ks_ttyline:
        ld      a,b
        or      a
        jr      nz,.inval
        ld      a,c
        cp      TTY_LINE
        jr      nc,.inval
        call    um_check                ; refused, not written through
        ret     c
        call    vfs_begin
        push    bc
        ld      de,VV_PATH              ; the bytes, in
        call    um_in
        pop     bc
        ld      ix,(K_LDSTATE)
        ld      iy,(K_CONCUR)
        ld      a,(ix+LD_OPEN)
        or      a
        jr      nz,.open
        xor     a                       ; nothing open: a line at the cursor
        ld      (ix+LD_LEN),a
        ld      (ix+LD_POS),a
        ld      (ix+LD_CUR),a
        ld      a,(iy+1)                ; con_col
        ld      (ix+LD_COL),a
        ld      a,1
        ld      (ix+LD_OPEN),a
.open:  push    bc
        ld      a,15h                   ; ^U: the old line's cells blanked
        call    ks_tty_key
        pop     bc
        ld      (ix+LD_LEN),c
        ld      a,c
        or      a
        jr      z,.set
        push    ix
        pop     hl
        ld      de,LD_BUF
        add     hl,de
        ex      de,hl                   ; de -> the line's bytes
        ld      hl,SG+VV_PATH
        ld      b,0
        ldir
.set:   call    ks_tty_set              ; written, the cursor at its end
        xor     a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret
