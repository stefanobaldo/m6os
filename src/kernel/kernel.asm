; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The resident kernel image: everything that lives in page 3 once m6 owns
; the machine. Assembled at K_BASE into build/kernel.bin; a loader copies it
; there after filling the capture record, then jumps to K_ENTRY.
;
; What is here: slot switching, the interrupt entry, the console and its
; VDP backend, the keyboard, the Nextor driver call, the segment
; allocator, the kernel window and the syscall gate, the scheduler and its
; process table, the process, the resident syscalls, and init. The boot
; sequence — k_main, the font's move, mapper detection, the loading of the
; switched part (boot.asm) — runs once and lies under the pipe buffers, which overwrite
; it; the scheduler's first row is
; set up from the switched part (KS_BOOT). The cold part of the kernel is
; that second image, kseg.asm, switched into page 2 on demand; it calls
; the resident through K_API and K_API2. The image includes the tests'
; shared definitions for the mailbox and the debug device. The stack is
; the last thing in the image and its top is K_END; a loader may put a
; program's own block above it.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"

        org     K_BASE
        jp      k_main
        jp      k_isr
k_ticks:
        dw      0
        dw      k_end
        dw      k_sslot_stub
k_probe:
        db      0
k_probe_slot:
        db      0
k_kseg:
        db      0
k_page1:
        db      0
k_api:
        jp      con_puts                ; API_CON_PUTS
        jp      con_putc                ; API_CON_PUTC
        jp      con_newline             ; API_CON_NEWLINE
        jp      con_hex8                ; API_CON_HEX8
        jp      con_hex16               ; API_CON_HEX16
        jp      con_dec16               ; API_CON_DEC16
        jp      nx_rw                   ; API_NX_RW
        jp      k_enaslt                ; API_K_ENASLT
        jp      mem_alloc               ; API_MEM_ALLOC
        jp      mem_free                ; API_MEM_FREE
        jp      mem_free_all            ; API_MEM_FREE_ALL
        jp      mem_info                ; API_MEM_INFO
        jp      spawn                   ; API_SPAWN
        jp      sys_wait                ; API_WAIT
        jp      sys_yield               ; API_YIELD
        jp      sys_read                ; API_READ
        jp      blk_rw                  ; API_BLK_RW
        jp      blk_dev_rw              ; API_BLK_DEV_RW
        jp      k_copy                  ; API_K_COPY
        jp      blk_query               ; API_BLK_QUERY
        jp      KS_BGET                 ; API_BGET: in the switched part
        jp      KS_BWRITE               ; API_BWRITE
        jp      KS_BDROP                ; API_BDROP
        jp      KS_BINVAL               ; API_BINVAL
        jp      KS_BREAD_DIRECT         ; API_BREAD_DIRECT
        jp      KS_BWRITE_DIRECT        ; API_BWRITE_DIRECT
        jp      KS_RTC_READ             ; API_RTC_READ
        jp      exec_finish             ; API_EXEC_FINISH
        jp      KS_BFLUSH               ; API_BFLUSH: in the switched part
        jp      KS_BZERO                ; API_BZERO
        jp      con_write               ; API_CON_WRITE
        jp      tty_row_read            ; API_ROW_READ (tty.asm)
        block   K_SYS-$
k_sys:
        jp      sys_exit                ; SYS_EXIT
        jp      sys_write               ; SYS_WRITE
        jp      sys_getpid              ; SYS_GETPID
        jp      k_sw_sysconf            ; SYS_SYSCONF, in the switched part
        jp      spawn                   ; SYS_SPAWN
        jp      sys_wait                ; SYS_WAIT
        jp      sys_yield               ; SYS_YIELD
        jp      sys_read                ; SYS_READ
        jp      sys_fork                ; SYS_FORK
        jp      sys_vfork               ; SYS_VFORK
        jp      k_sw_open               ; SYS_OPEN, in the switched part
        jp      sys_close               ; SYS_CLOSE: a pipe end here, the
                                        ; rest in the switched part
        jp      k_sw_lseek              ; SYS_LSEEK
        jp      k_sw_stat               ; SYS_STAT
        jp      k_sw_readdir            ; SYS_READDIR
        jp      k_sw_chdir              ; SYS_CHDIR
        jp      k_sw_exec               ; SYS_EXEC
        jp      k_sw_unlink             ; SYS_UNLINK
        jp      k_sw_mkdir              ; SYS_MKDIR
        jp      k_sw_rmdir              ; SYS_RMDIR
        jp      k_sw_rename             ; SYS_RENAME
        jp      sys_pipe                ; SYS_PIPE (pipe.asm)
        jp      k_sw_spawnv             ; SYS_SPAWNV, in the switched part
        jp      sys_waitpid             ; SYS_WAITPID (proc.asm)
        jp      sys_sleep               ; SYS_SLEEP (px.asm)
        jp      k_sw_procinfo           ; SYS_PROCINFO, in the switched part
        jp      k_sw_getcwd             ; SYS_GETCWD, in the switched part
        jp      k_sw_time               ; SYS_TIME, the same
        jp      k_sw_chmod              ; SYS_CHMOD, the same
        jp      k_sw_ttymode            ; SYS_TTYMODE, in the switched part
        jp      k_sw_kill               ; SYS_KILL, the same
        jp      k_sw_signal             ; SYS_SIGNAL, the same
        jp      k_sw_ttyline            ; SYS_TTYLINE, the same
        jp      k_sw_dosenter           ; SYS_DOSENTER, the same
        jp      k_sw_segalloc           ; SYS_SEGALLOC, the same
        jp      k_sw_segfree            ; SYS_SEGFREE, the same
        jp      k_sw_segmap             ; SYS_SEGMAP, the same
        DUP     K_SYS_N-SYS_N
        jp      sys_enosys
        EDUP
k_rec:  ds      KREC_SIZE
        block   K_KBDLAST-$             ; where the record grows
k_kbdlast:
        dw      kbd_last                ; what the switched part reaches by
k_ldstate:                              ; address (kernel.inc)
        dw      ld_state
k_concur:
        dw      con_row
k_dostmpl:
        dw      dos_tmpl
k_vol:  ds      VOL_N*VOL_SIZE          ; the volume table (blk.asm)
k_nvol: db      0
k_root: db      VOL_NONE
k_bcalls:
        dw      0
k_lasterr:
        db      0
k_dospid:
        db      0                       ; the legacy process's pid (dos.asm)
k_dosp0:
        db      0                       ; and its original page-0 segment
k_nrun: db      0                       ; rows in the ring (sched.asm)
        block   K_MAP-$
k_map:  ds      4                       ; the segment in each page
k_cur:  dw      K_PROC                  ; the current row (sched.asm)
k_pid:  dw      0                       ; the current pid; the high byte stays 0
        block   K_PROC-$
k_proc: ds      NPROC*P_SIZE            ; the process table, one aligned page
k_fd:   ds      NPROC*NOFILE            ; the descriptor table (proc.asm)
k_px:   ds      NPROC*PX_SIZE           ; the extension table (px.asm)
k_pipebuf:                              ; the pipe buffers (pipe.asm), and
        include "kernel/boot.asm"       ; under them the boot-once code,
                                        ; which the first pipe overwrites
        block   K_PIPEBUF+NPIPE*256-$   ; the overlay's ceiling: 1024 bytes
k_api2:
        jp      mem_own                 ; API2_MEM_OWN
        jp      mem_release             ; API2_MEM_RELEASE
        jp      mem_owner_of            ; API2_MEM_OWNER
        jp      con_init                ; API2_CON_INIT
        jp      kbd_init                ; API2_KBD_INIT
        jp      vdp_clear_rows          ; API2_VDP_CLEAR_ROWS
        jp      px_row                  ; API2_PX_ROW
        jp      sig_send                ; API2_SIG_SEND
        jp      sig_bit                 ; API2_SIG_BIT
        jp      sig_stub                ; API2_SIG_STUB
        jp      con_cursor              ; API2_CON_CURSOR
        jp      dos_tail                ; API2_DOS_TAIL
        ASSERT  k_ticks == K_TICKS
        ASSERT  k_probe == K_PROBE
        ASSERT  k_probe_slot == K_PROBE_SLOT
        ASSERT  k_kseg == K_KSEG
        ASSERT  k_page1 == K_PAGE1
        ASSERT  k_api == K_API
        ASSERT  k_sys == K_SYS
        ASSERT  k_rec == K_REC
        ASSERT  k_kbdlast == K_KBDLAST
        ASSERT  k_ldstate == K_LDSTATE
        ASSERT  k_concur == K_CONCUR
        ASSERT  k_dostmpl == K_DOSTMPL
        ASSERT  k_vol == K_VOL
        ASSERT  k_nvol == K_BLK_NVOL
        ASSERT  k_root == K_BLK_ROOT
        ASSERT  k_bcalls == K_BLK_CALLS
        ASSERT  k_lasterr == K_BLK_LASTERR
        ASSERT  k_dospid == K_DOSPID
        ASSERT  k_dosp0 == K_DOSP0
        ASSERT  k_nrun == K_NRUN
        ASSERT  k_map == K_MAP
        ASSERT  k_cur == K_CUR
        ASSERT  k_pid == K_PID
        ASSERT  k_proc == K_PROC
        ASSERT  k_fd == K_FD
        ASSERT  k_px == K_PX
        ASSERT  k_pipebuf == K_PIPEBUF
        ASSERT  k_api2 == K_API2
        ASSERT  $ == K_API2+3*API2_N

; The driver module's two external needs, supplied by this image: its own
; slot switch, and the RAM slot for page 1 as captured.
nx_enaslt       equ k_enaslt
nx_ramslot1     equ K_REC+KR_RAMAD+1
        define  NX_RW_ONLY              ; nx_find needs the BDOS; not here

        include "kernel/slot.asm"
        include "kernel/sslot.asm"
        include "kernel/irq.asm"
        include "kernel/vdp_t2.asm"
        include "kernel/con.asm"
        include "kernel/kbd.asm"
        include "nextor/abi2.asm"
        include "kernel/mem.asm"
        include "kernel/kwin.asm"
        include "kernel/blk.asm"
        include "kernel/sched.asm"
        include "kernel/proc.asm"
        include "kernel/px.asm"
        include "kernel/pipe.asm"
        include "kernel/sig.asm"
        include "kernel/tty.asm"
        include "kernel/dos.asm"
        include "kernel/sys.asm"
        include "kernel/main.asm"

; The syscall stack: what a switched syscall runs on, because the process's
; own stack may be in the page the window takes.
        ds      256
k_sstack:
; The stack: process 0's, and the boot's. Filled with a pattern so that
; a test can read how deep it went (K_STACK_LOW).
k_stack:
        block   256,0A5h
k_end:
        ASSERT  k_end <= K_HINGE        ; the hinge lies above the image

; Exported for programs that assemble a block to run at K_END, for a
; harness that wants to know when the kernel idles, and for a test that
; looks at the pipe table, the signal flag, the blocked-row counts, the
; terminal's line, the keyboard queue and the kernel stack's watermark.
K_IMAGE_END     equ k_end
K_STACK_LOW     equ k_stack
K_IMAGE_ROOF    equ K_HINGE             ; what the image must end below
K_IDLE_HALT     equ sched_idle_halt
K_PIPE_TAB      equ k_pipe
K_SIGFLAG       equ k_sigflag
K_KBWAIT        equ k_kbwait
K_NSLEEP        equ k_nsleep
K_PWAIT         equ k_pwait
K_TTY_MODE      equ tty_mode
K_LD_LEN        equ ld_len
K_KBCOUNT       equ kbd_count
        EXPORT  K_IMAGE_END
        EXPORT  K_STACK_LOW
        EXPORT  K_IMAGE_ROOF
        EXPORT  K_IDLE_HALT
        EXPORT  K_PIPE_TAB
        EXPORT  K_SIGFLAG
        EXPORT  K_KBWAIT
        EXPORT  K_NSLEEP
        EXPORT  K_PWAIT
        EXPORT  K_TTY_MODE
        EXPORT  K_KBCOUNT
        EXPORT  K_LD_LEN
