; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy subsystem's kernel half: a .COM program run with the machine
; to itself, the MSX-DOS 2 layout around it, served by a layer of code the
; program's launcher carries (src/leg/leg.asm, inside /bin/dos) and, for
; what needs the kernel, by the ordinary syscalls.
;
; While the program runs, page 3 shows a segment of its own — the legacy
; page 3: TPA to CFFFh, the layer from LEG_BASE, a copy of this page from
; K_HINGE up — and the resident's page 3 is out. The two meet at the
; hinge, K_HINGE_LEN bytes at the same address in both images, holding two
; stubs and a small stack: the first swaps the resident's page 3 in and
; points the page-0 interrupt vector at k_isr, the second swaps the legacy
; page 3 back and points it at the layer's trampoline, so that the vector
; always matches the page 3 in place. Every crossing is a DI region on the
; hinge's stack; the program's own stack, in the legacy copy of page 3, is
; never touched while the resident is in.
;
; The kernel's part is small and resident. A process that will become a
; program allocates segments (segalloc), maps two of them into its pages 1
; and 2 (segmap, which keeps them there across every switch) and fills a
; third with the layer and a copy of this page — all in user mode; then
; dosenter writes the hinge into both images, marks the process and
; crosses into the layer, which loads the program through read and enters
; it. A crossing back into the kernel carries a syscall: its arguments in
; A, HL, DE, BC as the syscall wants them (AF in AF' across the stub,
; which uses A), its number in C', and the segments the program has in
; pages 0-2 — its own or PUT_Pn's — in IXL, IXH, IYH, written to K_MAP
; first so that the gate restores what the program had and a transfer
; lands where the DOS says it does. k_dos_call runs the syscall with
; interrupts enabled, so a long disk call keeps the tick and pays an owed
; switch at its return like any process in a long syscall. The number
; LEG_EXIT means the program has ended: A is its DOS termination code,
; and the process exits with it as its status.
;
; One legacy process at a time: the hinge's stubs name its segments, and
; K_DOSPID in the header says whose they are.

; sys_dosenter — SYS_DOSENTER: A = the legacy page-3 segment, the
; caller's, filled by the caller as the layer expects; the caller's pages
; 1 and 2 hold the program's through segmap. The hinge into this page
; and into the legacy copy, the BIOS's cursor in that copy put where the
; console's is, the row marked, and the second stub taken. Never returns
; on success. E_PERM (process 0), E_BUSY (a legacy process exists),
; E_INVAL (a segment not the caller's).
sys_dosenter:
        ld      c,a
        ld      a,(k_pid)
        or      a
        jr      z,.perm
        ld      b,a
        ld      a,(K_DOSPID)
        or      a
        jr      nz,.busy
        ld      l,c
        ld      h,0
        ld      de,mem_owner
        add     hl,de
        ld      a,(hl)
        cp      b
        jr      nz,.inval
        ld      a,c
        ld      (kd_leg),a              ; the ldir below takes BC
        ; The hinge into this page: the template, its two segments patched.
        ld      hl,dos_tmpl
        ld      de,K_HINGE
        ld      bc,K_HINGE_STUBS
        ldir
        ld      a,(k_map+3)
        ld      (K_HINGE+1),a           ; this page's segment
        ld      a,(kd_leg)
        ld      (K_HINGE2+1),a          ; the legacy segment
        ; Into the legacy copy, through page 2, with the cursor.
        di
        out     (0FEh),a
        ld      hl,K_HINGE
        ld      de,K_HINGE-4000h
        ld      bc,K_HINGE_STUBS
        ldir
        ld      a,(con_row)
        inc     a
        ld      (B_CSRY-4000h),a
        ld      a,(con_col)
        inc     a
        ld      (B_CSRX-4000h),a
        ld      a,(k_map+2)
        out     (0FEh),a
        ; The row: three pages, its page 0 remembered, SIGINT ignored.
        ld      hl,(k_cur)
        ld      de,P_NPAGES
        add     hl,de
        ld      (hl),3
        inc     hl
        ld      a,(hl)
        ld      (K_DOSP0),a
        ld      a,(k_pid)
        ld      (K_DOSPID),a
        call    px_row
        ld      de,PX_SIGIGN
        add     hl,de
        set     0,(hl)                  ; SIGIGN_INT
        ld      sp,K_HINGE_SP
        jp      K_HINGE2
.perm:  ld      a,E_PERM
        scf
        ret
.busy:  ld      a,E_BUSY
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; dos_tmpl — the hinge's two stubs, K_HINGE_STUBS bytes copied to K_HINGE
; with the segment of each "ld a,n" patched. Position-independent but for
; the jumps, which are where they should be.
dos_tmpl:
        ld      a,0                     ; +1: this page's segment
        out     (0FFh),a
        ld      a,low K_ISR
        ld      (K_INTRPT+1),a
        ld      a,high K_ISR
        ld      (K_INTRPT+2),a
        jp      k_dos_call
        ld      a,0                     ; +18: the legacy segment
        out     (0FFh),a
        ld      a,low (LEG_VEC+6)
        ld      (K_INTRPT+1),a
        ld      a,high (LEG_VEC+6)
        ld      (K_INTRPT+2),a
        jp      LEG_VEC+3
        ASSERT  $-dos_tmpl == K_HINGE_STUBS

; k_dos_call — from the hinge's first stub: interrupts disabled, SP on the
; hinge's stack, this page in, the vector at k_isr. AF' holds the
; syscall's AF, C' its number, IXL/IXH/IYH the program's segments in pages
; 0-2. The syscall runs with interrupts enabled through its ordinary
; entry; the result — HL, and AF in AF' — goes back through the second
; stub to the layer's LEG_VEC+3.
k_dos_call:
        ex      af,af'
        push    af
        push    hl
        exx
        ld      a,c
        exx
        cp      LEG_EXIT
        jr      z,.exit
        ld      l,a
        add     a,a
        add     a,l                     ; ×3, at most 141
        add     a,low K_SYS             ; K_SYS is C070h: C070h+141 stays
        ld      l,a                     ; under C100h, so H is constant
        ld      h,high K_SYS
        ld      (kd_jp+1),hl
        push    ix
        pop     hl
        ld      (k_map+0),hl            ; K_MAP+0 = IXL, K_MAP+1 = IXH
        push    iy
        pop     hl
        ld      a,h
        ld      (k_map+2),a
        pop     hl
        pop     af
        ei
        call    kd_jp
        di
        ex      af,af'
        jp      K_HINGE2
.exit:  pop     hl
        pop     af
        jp      sys_exit                ; A = the code; k_dos_check inside
kd_jp:  jp      0                       ; the operand is the syscall's entry

; k_dos_check — the first thing sys_exit does, on the syscall stack, with
; interrupts as they were: nothing unless the dying process is the legacy
; one. Then: the process's original page 0 back in page 0, so that the
; interrupt vector is there whatever the program mapped; the PSG silenced;
; the console up again, keeping the screen and the cursor when the program
; left SCREEN 0 at 80 columns and clearing it otherwise — read from the
; BIOS variables in the legacy copy, through page 2; the keyboard's
; baseline taken from the matrix as it is, so a key still held does not
; register; K_DOSPID cleared. Preserves A (the status).
k_dos_check:
        push    af
        ld      hl,K_DOSPID
        ld      a,(k_pid)
        cp      (hl)
        jp      nz,.out
        ld      (hl),0
        di
        ld      a,(K_DOSP0)
        ld      (k_map+0),a
        out     (0FCh),a
        ei
        ld      a,8                     ; PSG channels A, B, C silent
        call    .psg0
        ld      a,9
        call    .psg0
        ld      a,10
        call    .psg0
        ld      a,(K_HINGE2+1)          ; the legacy segment, into page 2
        out     (0FEh),a
        ld      a,(B_SCRMOD-4000h)
        ld      (kd_scr),a
        ld      a,(B_LINLEN-4000h)
        ld      (kd_cols),a
        ld      a,(B_CSRY-4000h)
        ld      (kd_row),a
        ld      a,(B_CSRX-4000h)
        ld      (kd_col),a
        ld      a,(k_map+2)
        out     (0FEh),a
        call    con_init
        ld      a,(kd_scr)
        or      a
        jr      nz,.clear
        ld      a,(kd_cols)
        cp      CON_COLS
        jr      nz,.clear
        ld      a,(kd_row)
        dec     a
        cp      CON_ROWS
        jr      c,.row
        ld      a,CON_ROWS-1
.row:   ld      (con_row),a
        ld      a,(kd_col)
        dec     a
        cp      CON_COLS
        jr      c,.col
        xor     a
.col:   ld      (con_col),a
        jr      .kbd
.clear: xor     a
        ld      b,CON_ROWS
        call    vdp_clear_rows
        xor     a
        ld      (con_row),a
        ld      (con_col),a
.kbd:   call    kbd_init
        ld      hl,kbd_last             ; the matrix as it is now is the
        ld      b,11                    ; scan's baseline: a key still held
        ld      c,0                     ; — the RET that ended the program —
.row2:  in      a,(PPI_C)               ; is not a new press
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

; sys_segalloc — SYS_SEGALLOC: a segment for the caller, owner its pid,
; freed with everything else at its exit. Out: HL = A = the segment.
; E_NOMEM; E_PERM from process 0, whose segments nobody frees.
sys_segalloc:
        ld      a,(k_pid)
        or      a
        jr      z,.perm
        ld      b,a
        call    mem_alloc
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

; sys_segfree — SYS_SEGFREE: A = a segment: freed, when it is the caller's
; and not one of its pages. E_INVAL otherwise. Out: HL = 0.
sys_segfree:
        ld      hl,(k_cur)
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
        ld      hl,k_pid
        ld      b,(hl)
        call    mem_free
        jr      c,.inval
        ld      hl,0
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; sys_segmap — SYS_SEGMAP: A = a page, 1 or 2; B = a segment the caller
; owns. It becomes the process's page — P_SEG, K_MAP and the mapper — so
; that the gate and the scheduler keep it there. E_INVAL for another
; page or another owner. Out: HL = 0.
sys_segmap:
        dec     a
        cp      2
        jr      nc,.inval               ; page 0 or 3
        inc     a
        ld      c,a                     ; the page
        ld      l,b
        ld      h,0
        ld      de,mem_owner
        add     hl,de
        ld      a,(k_pid)
        cp      (hl)
        jr      nz,.inval
        ld      hl,(k_cur)
        ld      de,P_SEG
        add     hl,de
        ld      e,c
        ld      d,0
        add     hl,de
        di
        ld      (hl),b
        ld      hl,k_map
        add     hl,de
        ld      (hl),b
        ld      a,c
        add     a,0FCh
        ld      c,a
        out     (c),b
        ei
        ld      hl,0
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

kd_leg:         db 0            ; sys_dosenter: the legacy segment
kd_scr:         db 0            ; k_dos_check's readings of the legacy copy
kd_cols:        db 0
kd_row:         db 0
kd_col:         db 0
