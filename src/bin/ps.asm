; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; ps — every process, one per line under PID PPID ST PG: its pid, its
; parent's (- for none), its state as a letter — R runnable, W in wait,
; Z exited and not yet reaped, K reading the keyboard, V in vfork, P on
; a pipe, S in sleep — and its pages. The kernel keeps no command name,
; so none is shown. Reads the process rows through procinfo, whose
; layout is the kernel's own; ps is built with the kernel.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,s_head
        call    out_puts
        xor     a
        ld      (pid),a
.loop:  ld      a,(pid)
        ld      hl,row
        sys     SYS_PROCINFO
        jr      c,.next
        ld      a,(row+P_PID)
        ld      l,a
        ld      h,0
        ld      b,3
        call    out_dec16
        ld      a,' '
        call    out_putc
        ld      a,(row+P_PPID)
        cp      PP_NONE
        jr      nz,.ppid
        ld      hl,s_none
        call    out_puts
        jr      .state
.ppid:  ld      l,a
        ld      h,0
        ld      b,4
        call    out_dec16
.state: ld      a,' '
        call    out_putc
        ld      a,' '
        call    out_putc
        ld      a,(row+P_STATE)
        cp      PS_SLEEP+1
        jr      c,.known
        xor     a                       ; a state this table does not name
.known: ld      hl,s_state
        add     a,l
        ld      l,a
        jr      nc,.ltr
        inc     h
.ltr:   ld      a,(hl)
        call    out_putc
        ld      a,' '
        call    out_putc
        ld      a,(row+P_NPAGES)
        ld      l,a
        ld      h,0
        ld      b,2
        call    out_dec16
        ld      a,10
        call    out_putc
.next:  ld      hl,pid
        inc     (hl)
        ld      a,(hl)
        cp      NPROC
        jr      c,.loop
        xor     a
        ret

s_head:  db     "PID PPID ST PG",10,0
s_none:  db     "   -",0
s_state: db     "?RWZKVPS"              ; PS_FREE .. PS_SLEEP

        include "lib/out.inc"
        m6_bss
        bss     pid,1
        bss     row,PROCINFO_SIZE
