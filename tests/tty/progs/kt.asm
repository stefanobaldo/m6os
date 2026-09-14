; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; kt — kill and signal, every refusal and every effect, from a process:
; exits with the number of the first check that fails, and — the last
; check being kill of itself — never returns at all when every one
; passes: the test expects 143.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1

; expect errno: after a syscall, CF must be set with A = the errno, else
; exit with the check's number in (chk).
    macro expect_err Q1
        jp      nc,fail
        cp      Q1
        jp      nz,fail
    endm
    macro check Q1
        ld      a,Q1
        ld      (chk),a
    endm

start:
        check   1                       ; kill(0): EPERM
        xor     a
        ld      b,SIGTERM
        sys     SYS_KILL
        expect_err E_PERM
        check   2                       ; kill(16): EINVAL
        ld      a,NPROC
        ld      b,SIGTERM
        sys     SYS_KILL
        expect_err E_INVAL
        check   3                       ; a signal that is none of the four
        ld      a,1
        ld      b,7
        sys     SYS_KILL
        expect_err E_INVAL
        check   4                       ; a free row: ESRCH
        ld      a,NPROC-1
        ld      b,SIGTERM
        sys     SYS_KILL
        expect_err E_SRCH
        check   5                       ; signal(SIGKILL): EINVAL
        ld      a,SIGKILL
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        expect_err E_INVAL
        check   6                       ; signal(7): EINVAL
        ld      a,7
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        expect_err E_INVAL
        check   7                       ; signal returns the action that was
        ld      a,SIGTERM
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        jp      c,fail
        ld      a,l
        cp      SIG_DFL
        jp      nz,fail
        check   8
        ld      a,SIGTERM
        ld      b,SIG_DFL
        sys     SYS_SIGNAL
        jp      c,fail
        ld      a,l
        cp      SIG_IGN
        jp      nz,fail
        check   9                       ; SIGTERM ends a sleeping child: 143
        ld      hl,p_nap
        ld      de,av_nap
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        jp      c,fail
        ld      (pid),a
        ld      hl,2
        sys     SYS_SLEEP
        ld      a,(pid)
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,fail
        ld      a,(pid)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,l
        cp      128+SIGTERM
        jp      nz,fail
        check   10                      ; a zombie: success, nothing happens
        ld      hl,p_tiny
        ld      de,av_none
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        jp      c,fail
        ld      (pid),a
        ld      hl,2
        sys     SYS_SLEEP               ; tiny has exited: a zombie
        ld      a,(pid)
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,fail
        ld      a,(pid)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,l
        or      a
        jp      nz,fail                 ; its own status, 0
        check   11                      ; ignored: nothing; SIGKILL: 137
        ld      hl,p_ignall
        ld      de,av_none
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        jp      c,fail
        ld      (pid),a
        ld      hl,2
        sys     SYS_SLEEP
        ld      a,(pid)
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,fail
        ld      hl,2
        sys     SYS_SLEEP
        ld      a,(pid)
        ld      b,WNOHANG
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,h
        or      l
        jp      nz,fail                 ; it must still be alive
        ld      a,(pid)
        ld      b,SIGKILL
        sys     SYS_KILL
        jp      c,fail
        ld      a,(pid)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,l
        cp      128+SIGKILL
        jp      nz,fail
        check   12                      ; the mask is inherited by spawnv
        ld      a,SIGTERM
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,p_mask
        ld      de,av_none
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        jp      c,fail
        ld      b,0
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,l
        and     SIGIGN_TERM
        jp      z,fail
        check   13                      ; spawnv's A: SIGTERM taken by default,
        ld      a,SIGINT                ; SIGINT still ignored
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        ld      hl,p_mask
        ld      de,av_none
        ld      bc,m_inh
        ld      a,SIGIGN_TERM
        sys     SYS_SPAWNV
        jp      c,fail
        ld      b,0
        sys     SYS_WAITPID
        jp      c,fail
        ld      a,l
        and     SIGIGN_INT|SIGIGN_TERM
        cp      SIGIGN_INT
        jp      nz,fail
        ld      a,SIGINT
        ld      b,SIG_DFL
        sys     SYS_SIGNAL
        ld      a,SIGTERM
        ld      b,SIG_DFL
        sys     SYS_SIGNAL
        check   14                      ; kill of oneself: never returns
        sys     SYS_GETPID
        ld      a,l
        ld      b,SIGTERM
        sys     SYS_KILL
fail:   ld      a,(chk)
        sys     SYS_EXIT

chk:    db      0
pid:    db      0
p_nap:  db      "/bin/nap",0
s_120:  db      "120",0
av_nap: dw      p_nap,s_120,0
p_tiny: db      "/bin/tiny",0
p_ignall: db    "/bin/ignall",0
p_mask: db      "/bin/mask",0
av_none: dw     0
m_inh:  db      0FFh,0FFh,0FFh
