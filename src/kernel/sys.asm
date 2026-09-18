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
        k_sw_stub KS_CLOSE

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

; The K_SYS entry of every switched syscall: its stub (kwin.asm). The
; filesystem's run under the storage gate too, through k_sw_s.
k_sw_sysconf:
        k_switched KS_SYSCONF
k_sw_open:
        k_sw_stub KS_OPEN
k_sw_close:
        k_sw_stub KS_CLOSE
k_sw_lseek:
        k_sw_stub KS_LSEEK
k_sw_stat:
        k_sw_stub KS_STAT
k_sw_readdir:
        k_sw_stub KS_READDIR
k_sw_chdir:
        k_sw_stub KS_CHDIR
k_sw_exec:
        k_sw_stub KS_EXEC
k_sw_read:
        k_sw_stub KS_READ
k_sw_unlink:
        k_sw_stub KS_UNLINK
k_sw_mkdir:
        k_sw_stub KS_MKDIR
k_sw_rmdir:
        k_sw_stub KS_RMDIR
k_sw_rename:
        k_sw_stub KS_RENAME
k_sw_spawnv:
        k_sw_stub KS_SPAWNV
k_sw_getcwd:
        k_sw_stub KS_GETCWD
k_sw_chmod:
        k_sw_stub KS_CHMOD
k_sw_time:
        k_sw_stub KS_RTC_READ           ; SYS_TIME is the clock's reading
k_sw_procinfo:
        k_sw_stub KS_PROCINFO
k_sw_segalloc:
        k_sw_stub KS_SEGALLOC
k_sw_segfree:
        k_sw_stub KS_SEGFREE
k_sw_segmap:
        k_sw_stub KS_SEGMAP
k_sw_kill:
        k_sw_stub KS_KILL
k_sw_signal:
        k_sw_stub KS_SIGNAL
k_sw_dosenter:
        k_sw_stub KS_DOSENTER
k_sw_ttymode:
        k_sw_stub KS_TTYMODE
k_sw_ttyline:
        k_sw_stub KS_TTYLINE

