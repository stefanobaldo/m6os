; The process: what one is, how it is created, how it runs, how it ends.
;
; A process owns pages 0-2, 48K. Page 0 opens with the kernel's region —
; a jump to the exit stub at 0000h, the interrupt vector at 0038h, the
; subslot stub at 0040h, the exit stub itself at P0_EXIT — and the program
; starts at P0_PROG, as a .COM does. Its initial stack pointer is two below
; the top of its highest page, with P0_EXIT on the stack, so a program that
; ends in ret exits with status 0. Everything else is the program's.
;
; There is one process here, proc_cur, whose record has the layout a
; process table's row will have. proc_run is synchronous: it maps the
; process in, jumps to it, and returns with its exit status when the
; process calls exit — the kernel waits. A scheduler is what removes the
; wait, not this file.

; proc_create — HL = the program image, in pages 0-1 of the caller's
; memory; BC = its length; A = pages, 1-3. Out: CF clear and A = the pid;
; CF set with A = E_INVAL (pages not 1-3, length 0, image not in pages
; 0-1, or too long for the pages) or E_NOMEM (a segment short — nothing
; kept). Corrupts everything.
proc_create:
        or      a
        jp      z,.inval
        cp      4
        jp      nc,.inval
        ld      (proc_cur+P_NPAGES),a
        ld      (pc_src),hl
        ld      (pc_rem),bc
        ld      a,b
        or      c
        jp      z,.inval
        ld      a,h
        cp      80h
        jp      nc,.inval               ; the image is not in pages 0-1
        ld      a,(proc_cur+P_NPAGES)
        rrca
        rrca                            ; pages * 40h: 40h, 80h, C0h
        ld      h,a
        ld      l,0                     ; hl = pages * 4000h, the top
        dec     hl
        dec     hl
        ld      (proc_cur+P_SP),hl      ; the initial stack pointer
        inc     hl
        inc     hl
        ld      de,P0_PROG
        or      a
        sbc     hl,de                   ; the room for the program
        or      a
        sbc     hl,bc                   ; minus its length
        jp      c,.inval                ; it does not fit
        ; The segments.
        ld      a,(proc_cur+P_NPAGES)
        ld      c,a
        ld      hl,proc_cur+P_SEG
.alloc: ld      a,(proc_cur+P_PID)
        ld      b,a
        call    mem_alloc
        jr      c,.nomem
        ld      (hl),a
        inc     hl
        dec     c
        jr      nz,.alloc
        ; Each page in turn through the window: the header in page 0, the
        ; program's slice in every page it reaches.
        ld      hl,P0_PROG
        ld      (pc_dst),hl
        ld      a,(proc_cur+P_NPAGES)
        ld      c,a                     ; c = pages left
        ld      b,0                     ; b = this page
        ld      hl,proc_cur+P_SEG
.page:  ld      a,(hl)
        out     (0FEh),a
        push    hl
        push    bc
        ld      a,b
        or      a
        call    z,pc_header
        ld      hl,(pc_rem)
        ld      a,h
        or      l
        jr      z,.copied
        ld      de,(pc_dst)             ; where the next byte goes, in the
        ld      a,d                     ; process's addresses
        and     3Fh
        or      80h
        ld      d,a                     ; de = the same, in the window
        ld      hl,0C000h
        or      a
        sbc     hl,de                   ; hl = room left in this page
        ld      bc,(pc_rem)
        push    hl
        or      a
        sbc     hl,bc                   ; room - remaining
        pop     hl
        jr      c,.chunk                ; less room than remains: the room
        ld      h,b
        ld      l,c                     ; all that remains fits
.chunk: ld      b,h
        ld      c,l                     ; bc = this page's slice
        ld      hl,(pc_src)
        push    bc
        ldir
        ld      (pc_src),hl
        pop     bc
        ld      hl,(pc_dst)
        add     hl,bc
        ld      (pc_dst),hl
        ld      hl,(pc_rem)
        or      a
        sbc     hl,bc
        ld      (pc_rem),hl
.copied:
        pop     bc
        pop     hl
        inc     hl
        inc     b
        dec     c
        jr      nz,.page
        ; The highest page is in the window: the exit stub's address on the
        ; stack, for the program's final ret.
        ld      hl,P0_EXIT
        ld      (KS_BASE+3FFEh),hl
        ld      a,(k_map+2)
        out     (0FEh),a
        xor     a
        ld      (proc_cur+P_STATUS),a
        ld      a,(proc_cur+P_PID)      ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.nomem: ld      a,(proc_cur+P_PID)
        ld      b,a
        call    mem_free_all            ; whatever was taken, back
        ld      a,E_NOMEM
        scf
        ret

; pc_header — page 0 of the process is in the window: zero the kernel's
; region and write its four entries. Corrupts AF, BC, DE, HL.
pc_header:
        ld      hl,KS_BASE
        ld      (hl),0
        ld      de,KS_BASE+1
        ld      bc,P0_PROG-1
        ldir
        ld      a,0C3h
        ld      (KS_BASE),a             ; 0000h: jp P0_EXIT
        ld      hl,P0_EXIT
        ld      (KS_BASE+1),hl
        ld      (KS_BASE+K_INTRPT),a    ; 0038h: jp K_ISR
        ld      hl,K_ISR
        ld      (KS_BASE+K_INTRPT+1),hl
        ld      hl,(K_STUB)             ; 0040h: the subslot stub
        ld      de,KS_BASE+K_SSLOT
        ld      bc,K_SSLOT_LEN
        ldir
        ld      hl,KS_BASE+P0_EXIT      ; P0_EXIT: xor a; jp exit
        ld      (hl),0AFh
        inc     hl
        ld      (hl),0C3h
        inc     hl
        ld      de,K_SYS+3*SYS_EXIT
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; proc_run — run proc_cur: its pages in, its stack, its program. Returns
; when the process exits, with A = its status. Corrupts everything.
proc_run:
        ld      (k_ksp),sp
        ld      hl,proc_cur+P_SEG
        ld      a,(hl)
        ld      (k_map+0),a
        out     (0FCh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+1),a
        out     (0FDh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+2),a
        out     (0FEh),a
        ld      sp,(proc_cur+P_SP)
        jp      P0_PROG

; sys_exit — SYS_EXIT: A = status. The kernel's stack and pages back, the
; process's segments freed, and proc_run returns.
sys_exit:
        ld      (proc_cur+P_STATUS),a
        ld      sp,(k_ksp)
        ld      hl,K_REC+KR_SEG64K
        ld      a,(hl)
        ld      (k_map+0),a
        out     (0FCh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+1),a
        out     (0FDh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+2),a
        out     (0FEh),a
        ld      a,(proc_cur+P_PID)
        ld      b,a
        call    mem_free_all
        ld      a,(proc_cur+P_STATUS)
        ret

proc_cur:
        dw      1                       ; P_PID
        ds      P_SIZE-2
k_ksp:          dw 0            ; the kernel's stack pointer while a
                                ; process runs
pc_src:         dw 0            ; proc_create: the next byte of the image
pc_dst:         dw 0            ;   where it goes, in the process's addresses
pc_rem:         dw 0            ;   bytes left
