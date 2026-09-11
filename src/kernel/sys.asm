; The resident syscalls: the ones on the hot path, whose K_SYS entry jumps
; straight to the body. exit, spawn, wait, yield, fork and vfork are in
; proc.asm, read in kbd.asm; sysconf is in the switched part (kseg.asm). Convention as kernel.inc states it: arguments in A, HL,
; DE, BC; result in HL; CF set with the errno in A; nothing else preserved.

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
; that is the console writes there. Out: HL = bytes written; CF and E_BADF
; for any other descriptor — a file's, until the write side exists.
sys_write:
        call    fd_code
        cp      FD_CON
        jr      z,.con
        ld      a,E_BADF
        scf
        ret
.con:   push    bc
        call    con_write               ; the whole buffer, scrolled once
        pop     hl                      ; the length, all of it written
        or      a                       ; CF clear
        ret

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
