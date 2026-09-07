; The resident syscalls: the ones on the hot path, whose K_SYS entry jumps
; straight to the body. exit is in proc.asm; sysconf is in the switched
; part (kseg.asm). Convention as kernel.inc states it: arguments in A, HL,
; DE, BC; result in HL; CF set with the errno in A; nothing else preserved.

; sys_write — SYS_WRITE: A = fd, HL = buffer, BC = length. fd 1 and 2 are
; the console. Out: HL = bytes written; CF and E_BADF for any other fd.
sys_write:
        cp      1
        jr      z,.con
        cp      2
        jr      z,.con
        ld      a,E_BADF
        scf
        ret
.con:   push    bc
.next:  ld      a,b
        or      c
        jr      z,.done
        ld      a,(hl)
        call    con_putc                ; preserves BC, DE, HL
        inc     hl
        dec     bc
        jr      .next
.done:  pop     hl                      ; the length, all of it written
        or      a                       ; CF clear
        ret

; sys_getpid — SYS_GETPID. Out: HL = pid.
sys_getpid:
        ld      hl,(proc_cur+P_PID)
        or      a
        ret

; sys_enosys — every K_SYS entry not yet given a syscall.
sys_enosys:
        ld      a,E_NOSYS
        scf
        ret

; The K_SYS entry of every switched syscall: its stub (kwin.asm).
k_sw_sysconf:
        k_switched KS_SYSCONF
