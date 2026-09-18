; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The resident syscalls: the ones on the hot path, whose K_SYS entry jumps
; straight to the body. exit, spawn, wait, waitpid, yield, fork and vfork
; are in proc.asm, read in kbd.asm, pipe in pipe.asm, sleep in px.asm;
; sysconf is in the switched part (kseg.asm), and so are the cold ones —
; procinfo, segalloc, segfree, segmap, kill, signal, dosenter, ttymode,
; ttyline (ks_sys.asm) — whose
; stubs are here with the filesystem's. Convention as kernel.inc states
; it: arguments in A, HL, DE, BC; result in HL; CF set with the errno in
; A; nothing else preserved.

; fd_code — A = a descriptor: A = its byte in the current process's row of
; the descriptor table (FD_NONE for one at or past NOFILE). Preserves BC,
; HL; corrupts DE.
fd_code:
        cp      NOFILE
        jr      nc,.none
        ld      e,a
        ld      a,(k_pid)
        add     a,a
        add     a,a
        add     a,a
        add     a,e
        ld      e,a
        ld      d,high K_FD             ; K_FD is page aligned
        ld      a,(de)
        ret
.none:  ld      a,FD_NONE
        ret

; sys_write — SYS_WRITE: A = fd, HL = buffer, BC = length. A descriptor
; that is the console writes there, without leaving the resident, and so
; does a pipe's write end (pipe.asm); one that names an open file goes to
; the switched part with A = the open-file row's index. Out: HL = bytes
; written; CF and E_BADF for the keyboard, a pipe's read end or a closed
; descriptor.
sys_write:
        call    fd_code
        cp      FD_CON
        jr      z,.con
        cp      80h
        jr      c,.file
        cp      FD_PIPE_W
        jr      c,.badf
        cp      FD_PIPE_W+NPIPE
        jp      c,pipe_write            ; a pipe's write end (pipe.asm)
.badf:  ld      a,E_BADF
        scf
        ret
.file:  ld      ix,KS_WRITE
        jp      k_sw_s
.con:   push    bc
        call    con_write               ; the whole buffer, scrolled once
        pop     hl                      ; the length, all of it written
        ld      a,(k_owed)
        or      a                       ; CF clear
        jp      nz,k_owed_con           ; a switch owed while it wrote
        ret

; sys_close — SYS_CLOSE: A = fd. A pipe end is closed here — the slot
; freed, the pipe's count down, its waiters woken — and everything else
; in the switched part (ks_close), which owns the open-file table.
sys_close:
        ld      c,a
        call    fd_code                 ; a = the byte, de -> it
        cp      FD_PIPE_R
        jr      c,.sw
        cp      FD_PIPE_W+NPIPE
        jr      nc,.sw
        ex      de,hl
        ld      (hl),FD_NONE
        call    pipe_unref
        xor     a                       ; CF clear
        ret
.sw:    ld      a,c
        jp      k_sw_close

; sys_getpid — SYS_GETPID. Out: HL = pid.
sys_getpid:
        ld      hl,(k_pid)
        or      a
        ret

; sys_enosys — every K_SYS entry not yet given a syscall.
sys_enosys:
        ld      a,E_NOSYS
        scf
        ret

; sysconf's K_SYS entry: the plain switched call, k_switched, with no
; storage gate and no indirection — it is the switched round trip the
; process test measures against its line, and it stays what was measured.
; Every other switched syscall's stub stands beside k_sw_s (kwin.asm).
k_sw_sysconf:
        k_switched KS_SYSCONF
