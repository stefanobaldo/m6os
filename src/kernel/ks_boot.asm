; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The boot's tail, in the switched part: the scheduler's first row and the
; release of the loader's pages, run once by k_main through the window as
; soon as the switched image is loaded (KS_BOOT, ks_boot). Both write the
; header's fields only — K_PROC, K_FD, K_PX, K_MAP, K_CUR, K_PID, K_NRUN —
; and reach the allocator's two boot-time entries through K_API2, so they
; depend on the contract and not on the resident's layout; nothing here is
; needed again, which is why it is not resident.

ks_boot:
        call    sched_init
        jp      sched_release_boot

; sched_init — row 0 and the scalars, before anything runs. Corrupts
; everything. Reached through KS_BOOT.
sched_init:
        ld      hl,K_PROC
        ld      (hl),PS_FREE
        ld      de,K_PROC+1
        ld      bc,NPROC*P_SIZE-1
        ldir
        ld      hl,K_PROC
        ld      (hl),PS_RUN             ; process 0: runnable, pid 0, a
        ld      (K_CUR),hl              ; ring of one
        ld      a,low K_PROC
        ld      (K_PROC+P_NEXT),a
        ld      hl,0
        ld      (K_PID),hl
        ld      a,1
        ld      (K_NRUN),a
        ld      a,PP_NONE
        ld      (K_PROC+P_PPID),a
        ld      hl,K_MAP                ; its pages: what is mapped now,
        ld      de,K_PROC+P_SEG         ; until sched_release_boot
        ld      bc,3
        ldir
        ; Every descriptor closed, then process 0's three: the keyboard on
        ; 0, the console on 1 and 2.
        ld      hl,K_FD
        ld      (hl),FD_NONE
        ld      de,K_FD+1
        ld      bc,NPROC*NOFILE-1
        ldir
        ld      a,FD_KBD
        ld      (K_FD+0),a
        ld      a,FD_CON
        ld      (K_FD+1),a
        ld      (K_FD+2),a
        ; The extension table: zero, every row waiting on no pipe.
        ld      hl,K_PX
        ld      b,NPROC
.px:    ld      (hl),0FFh               ; PX_WCHAN
        inc     hl
        xor     a
        ld      c,PX_SIZE-1
.pxz:   ld      (hl),a
        inc     hl
        dec     c
        jr      nz,.pxz
        djnz    .px
        ret

; sched_release_boot — once the switched image is loaded: the boot
; segments of pages 0 and 1 go to the allocator, the boot segment of page
; 2 stays as the kernel's scratch page, and process 0's pages 0 and 1
; become the switched image's segment, which carries the vector and the
; stub. With a program to run that lies below page 3 (KR_TEST), the boot
; segment of the page it lies in is kept instead, as that page of process
; 0's: the program is there, where the loader's memory had it, and runs in
; place — a test whose block outgrew the room above the image in page 3,
; which is where a smaller one still goes. A block in page 1 is what most
; tests use; a block in page 0 is for one that switches page 1 away
; itself — the storage gate, a driver call, a slot switch. The loader
; wrote the vector and the stub into its page 0 before jumping here, so
; that page serves as process 0's as the switched image's segment does.
; With no switched image nothing changes hands. Corrupts everything.
sched_release_boot:
        ld      a,(K_KSEG)
        or      a
        ret     z
        ld      b,MEM_KERNEL
        k_call2 API2_MEM_OWN                ; the switched image's segment
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,MEM_KERNEL
        k_call2 API2_MEM_OWN                ; the scratch page
        ld      hl,(K_REC+KR_TEST)
        ld      a,h
        or      l
        jr      z,.rel                  ; nothing to run
        ld      a,h
        cp      40h
        jr      c,.keep0                ; a program in page 0
        cp      0C0h
        jr      c,.keep1                ; a program in page 1
.rel:   ld      a,(K_REC+KR_SEG64K+0)
        k_call2 API2_MEM_RELEASE
        ld      a,(K_REC+KR_SEG64K+1)
        k_call2 API2_MEM_RELEASE
        ld      a,(K_KSEG)
        jr      .page1
.keep1: ld      a,(K_REC+KR_SEG64K+0)
        k_call2 API2_MEM_RELEASE
        ld      a,(K_REC+KR_SEG64K+1)
        ld      b,MEM_KERNEL
        k_call2 API2_MEM_OWN                ; the program's page 1, kept
.page1: ld      (K_PROC+P_SEG+1),a
        ld      (K_MAP+1),a
        out     (0FDh),a
        ld      a,(K_KSEG)
        ld      (K_PROC+P_SEG+0),a
        ld      (K_MAP+0),a
        out     (0FCh),a                ; the vector is in the new page 0
        ret
.keep0: ld      a,(K_REC+KR_SEG64K+0)
        ld      b,MEM_KERNEL
        k_call2 API2_MEM_OWN                ; the program's page 0, kept: it is
        ld      (K_PROC+P_SEG+0),a      ; in page 0 and in K_MAP already
        ld      a,(K_REC+KR_SEG64K+1)
        k_call2 API2_MEM_RELEASE
        ld      a,(K_KSEG)
        ld      (K_PROC+P_SEG+1),a
        ld      (K_MAP+1),a
        out     (0FDh),a
        ret
