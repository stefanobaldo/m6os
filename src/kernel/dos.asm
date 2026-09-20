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
; page 3: TPA to LEG_BASE, the layer from there, a copy of this page from
; K_HINGE up — and the resident's page 3 is out. The two meet at the
; hinge, K_HINGE_LEN bytes at the same address in both images, holding two
; stubs and a small stack: the first swaps the resident's page 3 in and
; points the page-0 interrupt vector at k_isr, the second swaps the legacy
; page 3 back and points it at the layer's trampoline, so that the vector
; always matches the page 3 in place. Every crossing is a DI region on the
; hinge's stack; the program's own stack, in the legacy copy of page 3, is
; never touched while the resident is in.
;
; The kernel's part is small. A process that will become a program
; allocates segments (segalloc), maps two of them into its pages 1 and 2
; (segmap, which keeps them there across every switch) and fills a third
; with the layer and a copy of this page — all in user mode; then dosenter
; writes the hinge into both images, marks the process and crosses into
; the layer, which loads the program through read and enters it. What is
; resident is the crossing itself — k_dos_call, a hot path — the hinge's
; template, which names it, and dos_tail, the last step of dosenter,
; which gives the process its pages back and cannot run from the window
; it closes. The rest — dosenter, segalloc, segfree, segmap, and the
; exit's check that puts the console and the keyboard back — runs once
; per program and lives in the switched part (ks_sys.asm). A crossing back into the kernel carries a syscall: its arguments in
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

; dos_tail — API2_DOS_TAIL, from the switched dosenter (ks_sys.asm) with
; interrupts off and the hinge written: the process's pages 1 and 2 back
; — the storage gate and the window are left here, since the crossing
; never returns through the gate — and the second stub taken on the
; hinge's stack. Never returns.
dos_tail:
        k_stgate_leave
        kwin_leave
        ld      sp,K_HINGE_SP
        jp      K_HINGE2

