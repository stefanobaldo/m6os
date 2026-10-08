; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The boot's tail, in the switched part: the release of the loader's
; pages, run once by k_main through the window after the boot image has
; run (KS_BOOT, sched_release_boot). It remaps page 0 under its caller,
; which is why it runs from here, called from page 3, and not from the
; boot image in page 0. It writes the header's fields only — K_PROC,
; K_MAP — and reaches the allocator's two boot-time entries through
; K_API2, so it depends on the contract and not on the resident's
; layout; nothing here is needed again, which is why it is not resident.
; The scheduler's first row, which used to precede it here, is the boot
; image's (kboot.asm, sched_init).

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
