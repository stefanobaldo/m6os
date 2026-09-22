; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's body, the lend: the segment of the program's parent,
; given to the program when the kernel has none left. Included by leg.asm
; at LEG_BODY, after the FCB functions. On a 128K machine a .COM run
; from the shell finds all eight segments taken — three the kernel's,
; the shell's page, the program's four — where MSX-DOS 2 leaves one
; free, and a program that asks for one, or reads the free count before
; it runs another, gives up. The parent is frozen while the program runs
; — blocked in wait, and nothing else runs but in the program's own
; syscalls — so its page can be the program's for the run: counted free
; from the entry (legi.asm), written to /m6.swp on the boot volume when
; an ALL_SEG takes it, read back when the program ends. A program that
; never allocates it costs nothing but two procinfo calls at the entry.
;
; Reached through leg_ldoor (leg.asm), on the layer's stack with the body
; in and interrupts off: the lend maps the parent's segment into page 1
; for its transfers, where the program's stack or an interrupt hook of
; its own may lie. The allocator is never told: the segment stays the
; parent's there, so the program's exit does not free it.
LL_NONE         equ 0           ; ll_st: nothing to lend
LL_HOME         equ 1           ; the parent's segment in place
LL_LENT         equ 2           ; the program's, its bytes on the file
LL_FREED        equ 3           ; freed by the program, its bytes still
                                ;   on the file, lent again as it is

; ll_lend — ALL_SEG, the kernel out of segments: the parent's, if it can
; be lent. The parent must still be blocked in wait with the same page
; 0, since only that keeps it off the CPU during the program's syscalls.
; Out: CF clear and L = the segment, or CF.
ll_lend:
        ld      a,(ll_st)
        cp      LL_FREED
        jr      z,.again                ; its bytes are on the file already
        cp      LL_HOME
        scf
        ret     nz
        ld      a,(ll_ppid)
        ld      hl,leg_path2
        leg_sys SYS_PROCINFO
        ret     c
        ld      a,(leg_path2+P_STATE)
        cp      PS_WAIT
        scf
        ret     nz
        ld      a,(ll_seg)
        ld      hl,leg_path2+P_SEG
        cp      (hl)
        scf
        ret     nz
        xor     a
        ld      (ll_new),a
        ld      hl,s_swap
        ld      a,O_WRONLY              ; the file where it is, never emptied:
        leg_sys SYS_OPEN                ; a second lend writes over the
        jr      nc,.open                ; clusters of the first
        cp      E_NOENT
        scf
        ret     nz
        ld      hl,s_swap
        ld      a,O_WRONLY|O_CREAT
        leg_sys SYS_OPEN
        ret     c
        ld      a,1
        ld      (ll_new),a
.open:  ld      a,l
        ld      e,SYS_WRITE
        call    ll_io
        ret     c
        ld      a,(ll_new)
        or      a
        jr      z,.again
        ld      hl,s_swap               ; hidden, once closed; its failure
        ld      a,DA_HIDDEN             ; costs the attribute alone
        leg_sys SYS_CHMOD
.again: ld      a,LL_LENT
        ld      (ll_st),a
        ld      a,(ll_seg)
        ld      l,a
        or      a
        ret

; ll_unlend — FRE_SEG, the kernel refusing A: the lent segment, which is
; then the program's to have again. CF clear when A was it.
ll_unlend:
        ld      b,a
        ld      a,(ll_st)
        cp      LL_LENT
        scf
        ret     nz
        ld      a,(ll_seg)
        cp      b
        scf
        ret     nz
        ld      a,LL_FREED
        ld      (ll_st),a
        or      a
        ret

; ll_back — the program's end: the lent segment's bytes back from the
; file. If they cannot be read, the parent's memory is lost, and the
; parent is ended rather than resumed on it — at the keyboard the kernel
; starts a new shell.
ll_back:
        ld      a,(ll_st)
        cp      LL_LENT
        ret     c                       ; nothing lent
        ld      hl,s_swap
        ld      a,O_RDONLY
        leg_sys SYS_OPEN
        jr      c,.lost
        ld      a,l
        ld      e,SYS_READ
        call    ll_io
        ret     nc
.lost:  ld      a,(ll_ppid)
        ld      b,SIGKILL
        leg_sys SYS_KILL
        ret

; ll_io — A = the swap file's descriptor, E = SYS_WRITE or SYS_READ: the
; lent segment's 16K moved from the file's start, through page 1. The
; crossing tells the kernel what pages 0-2 hold (IXH for page 1), so the
; segment is named there for the call and the transfer lands in it; the
; program's page 1 is put back in the shadow and in the mapper after
; each call, with interrupts still off. The file is closed. CF when a
; call fails, moves nothing, or the close fails.
ll_io:
        ld      (ll_fd),a
        ld      a,e
        ld      (ll_op),a
        ld      hl,4000h
.more:  ld      (ll_at),hl
        ld      a,h
        cp      80h
        jr      z,.done                 ; all 16K: CF clear
        ex      de,hl
        ld      hl,8000h
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; what is left
        ex      de,hl
        ld      a,(leg_segs+1)
        ld      (ll_p1),a
        ld      a,(ll_seg)
        ld      (leg_segs+1),a
        ld      a,(ll_op)
        exx
        ld      c,a
        exx
        ld      a,(ll_fd)
        call    leg_syscall             ; HL = the bytes moved
        push    af
        ld      a,(ll_p1)
        ld      (leg_segs+1),a
        out     (0FDh),a
        pop     af
        jr      c,.done
        ld      a,h
        or      l
        scf
        jr      z,.done                 ; nothing moved: the volume is full
        ld      de,(ll_at)
        add     hl,de
        jr      .more
.done:  push    af
        ld      a,(ll_fd)
        leg_sys SYS_CLOSE
        pop     de
        ret     c
        push    de
        pop     af
        ret

s_swap: db      "/m6.swp",0
