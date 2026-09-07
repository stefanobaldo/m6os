; The resident kernel image and its contract with whatever loads it.
;
; The image is assembled at K_BASE (src/kernel/kernel.asm, build/kernel.bin)
; and copied there by a loader that has already filled the capture record
; (K_REC) from the environment it is leaving. The header at K_BASE — entry
; points, the jump table and the record — is the only thing a loader or a
; program needs to know about the image's insides.

K_BASE          equ 0C000h
K_ENTRY         equ K_BASE+0    ; JP k_main: the loader jumps here last
K_ISR           equ K_BASE+3    ; JP k_isr: the target of page 0's 0038h
K_TICKS         equ K_BASE+6    ; dw: ticks counted since k_irq_init
K_END           equ K_BASE+8    ; dw: first address after the image; also
                                ;     the top of the resident's stack, and
                                ;     where a loader puts a program's block
K_STUB          equ K_BASE+10   ; dw: address of the subslot stub image,
                                ;     K_SSLOT_LEN bytes, to copy to K_SSLOT
K_PROBE         equ K_BASE+12   ; db: the byte mapper detection writes when
                                ;     the segment under test is the one in
                                ;     page 3 (mem.asm); its page offset is
                                ;     the probe address in every segment
K_PROBE_SLOT    equ K_BASE+13   ; db: the slot being probed, for a harness
                                ;     to read if the scan never returns
K_KSEG          equ K_BASE+14   ; db: the segment holding the switched part
                                ;     of the kernel (kwin.asm); 0 until it
                                ;     is loaded, or when there is none
K_API           equ K_BASE+16   ; K_API_N entries of JP, 3 bytes each: what
                                ;     a kernel-side program calls in the
                                ;     resident; the order is fixed and only
                                ;     grows
K_API_N         equ 14
K_SYS           equ K_BASE+64   ; K_SYS_N entries of JP, 3 bytes each: the
                                ;     syscall table, what a process calls
                                ;     (sys.asm); an entry not yet given a
                                ;     syscall returns ENOSYS
K_SYS_N         equ 64
K_REC           equ K_BASE+256  ; the capture record, KREC_SIZE bytes

; The jump table's entries. Contracts are the routines' own (con.asm,
; abi2.asm, slot.asm, mem.asm).
API_CON_PUTS    equ 0           ; HL -> 0-terminated string
API_CON_PUTC    equ 1           ; A = character; 10 is a newline
API_CON_NEWLINE equ 2
API_CON_HEX8    equ 3           ; A
API_CON_HEX16   equ 4           ; HL
API_CON_DEC16   equ 5           ; HL, no leading zeros
API_NX_RW       equ 6           ; IX -> descriptor, Cy, B, HL, DE -> sector
API_K_ENASLT    equ 7           ; A = slot, HL = address; DI on return
API_MEM_ALLOC   equ 8           ; B = owner -> A = segment; CF if none
API_MEM_FREE    equ 9           ; A = segment, B = owner; CF if refused
API_MEM_FREE_ALL equ 10         ; B = owner
API_MEM_INFO    equ 11          ; -> HL, BC, DE, A
API_PROC_CREATE equ 12          ; HL image, BC length, A pages -> A pid; CF
API_PROC_RUN    equ 13          ; runs the process; -> A = its exit status

; k_call n — call the resident through the jump table.
    macro k_call n
        call    K_API+3*n
    endm

; The syscalls (sys.asm, proc.asm, kseg.asm) and their table indices. A
; process calls K_SYS+3*n. Arguments in A, HL, DE, BC as each syscall says;
; the result in HL (and A when it fits a byte); CF set on error with the
; errno in A. Nothing the syscall does not return is preserved: BC, DE, IX,
; IY and the alternate set are undefined afterwards.
SYS_EXIT        equ 0           ; A = status; does not return
SYS_WRITE       equ 1           ; A = fd (1, 2), HL = buffer, BC = length
                                ; -> HL = bytes written; EBADF
SYS_GETPID      equ 2           ; -> HL = pid
SYS_SYSCONF     equ 3           ; HL = SC_* -> HL = value; EINVAL
SYS_N           equ 4           ; entries given a syscall so far

    macro sys n
        call    K_SYS+3*n
    endm

SC_PAGESIZE     equ 0           ; 16384
SC_SEGMENTS     equ 1           ; segments in the primary mapper
SC_SEGMENTS_USABLE equ 2        ; the count, or the mem= cap
SC_SEGMENTS_FREE equ 3          ; free now

; Errnos: Seventh Edition's, with its numbers; ENOSYS with Linux's.
E_PERM          equ 1
E_NOENT         equ 2
E_SRCH          equ 3
E_INTR          equ 4
E_IO            equ 5
E_NXIO          equ 6
E_2BIG          equ 7
E_NOEXEC        equ 8
E_BADF          equ 9
E_CHILD         equ 10
E_AGAIN         equ 11
E_NOMEM         equ 12
E_ACCES         equ 13
E_FAULT         equ 14
E_BUSY          equ 16
E_EXIST         equ 17
E_NODEV         equ 19
E_NOTDIR        equ 20
E_ISDIR         equ 21
E_INVAL         equ 22
E_NFILE         equ 23
E_MFILE         equ 24
E_NOSPC         equ 28
E_ROFS          equ 30
E_PIPE          equ 32
E_NOSYS         equ 38

; The switched part of the kernel (kseg.asm): assembled at KS_BASE, the
; kernel window, and entered through its own jump table. Code and constants
; only — it may be a ROM bank.
KS_BASE         equ 8000h
KS_SYSCONF      equ KS_BASE+0   ; the body of SYS_SYSCONF
KS_SUMMARY      equ KS_BASE+3   ; the boot summary of the memory

; A process (proc.asm): what it sees in page 0, and its record.
P0_EXIT         equ 0060h       ; xor a; jp K_SYS+3*SYS_EXIT — where a
                                ; program's final ret lands, and jp 0's
P0_PROG         equ 0100h       ; where the program starts
P_PID           equ 0           ; 2: the pid; its low byte is the owner in
                                ;    the allocator
P_NPAGES        equ 2           ; pages, 1-3
P_SEG           equ 3           ; 3: the segment in each of pages 0-2
P_SP            equ 6           ; 2: the initial stack pointer
P_STATUS        equ 8           ; the exit status
P_SIZE          equ 9

; The capture record: what the resident needs to know about the machine,
; gathered by the loader while the previous system is still there. Every
; field is one byte unless noted. KR_CSRY is read last, just before the
; takeover, so that the resident's output continues under the loader's.
KR_RAMAD        equ 0           ; 4: RAM slot of each page (RAMAD0-3)
KR_SEG64K       equ 4           ; 4: mapper segment in each page
KR_CODESEG      equ 8           ; the previous kernel's code segment
KR_DATASEG      equ 9           ; the previous kernel's data segment
KR_MAPSLOT      equ 10          ; slot of the primary mapper (report only)
KR_MAPTOTAL     equ 11          ; its segment count as reported (report only)
KR_WALL         equ 12          ; 2: first page-3 address the resident must
                                ;    not touch (driver work areas start here)
KR_DOSHIM       equ 14          ; 2: top of the previous kernel's resident code
KR_TIMISAVE     equ 16          ; 5: H.TIMI as it was before that kernel
KR_FCALSAVE     equ 21          ; 5: FCALL as it was before that kernel
KR_VDPRD        equ 26          ; VDP read port (data; status is +1)
KR_VDPWR        equ 27          ; VDP write port (data; control is +1)
KR_NAMBAS       equ 28          ; 2: name table of the inherited text screen
KR_COLS         equ 30          ; characters per line in use
KR_STRIDE       equ 31          ; name-table bytes per row (40 or 80)
KR_ROWS         equ 32          ; rows on screen
KR_CSRY         equ 33          ; cursor row the previous system left, 1-based
KR_DRV          equ 34          ; 4: Nextor driver descriptor (NXD_*)
KR_FIRST        equ 38          ; 4: first device sector of the boot partition
KR_TARGET       equ 42          ; 4: device sector the test writes
KR_TPRE         equ 46          ; 2: ticks for 600 driver reads, pre-takeover
KR_TPRECMP      equ 48          ; 2: the same loop without the call, pre-takeover
KR_KSLOTS       equ 50          ; 4: the Nextor kernel slots found (report only)
KR_TEST         equ 54          ; 2: where k_main jumps after boot; 0 = halt
KR_MEMCAP       equ 56          ; usable segments of the primary mapper;
                                ; 0 = no cap (256 is therefore written as 0)
KR_KSEG_SRC     equ 57          ; 2: where the switched kernel image is, in
                                ;    pages 0-1 of the loader's memory; 0 =
                                ;    there is none
KR_KSEG_LEN     equ 59          ; 2: its length, 1 to 4000h
KREC_SIZE       equ 61

; Memory (mem.asm). Owners in the segment table; the mapper table's layout.
MEM_FREE        equ 0           ; owner: nobody
MEM_KERNEL      equ 0FEh        ; owner: the kernel; 01h-FDh are processes
MEM_RESERVED    equ 0FFh        ; absent, above the cap, or in use at boot:
                                ; never on the free stack, never freed
MEM_MAPS_MAX    equ 4           ; mappers the table holds; more are counted
MM_SLOT         equ 0           ; slot id, E000SSPP
MM_SEGS         equ 1           ; 2: segments, 1-256
MM_FLAGS        equ 3           ; MMF_*
MM_SIZE         equ 4
MMF_PRIMARY     equ 1           ; the mapper page 3 lives in

; Page 0. Every page 0 the kernel runs with carries these two things and
; nothing else is required of it: the interrupt entry, and the secondary
; slot switching stub, which must execute outside page 3 because writing
; FFFFh needs page 3 to show the slot being switched. MSX-DOS keeps its
; copy of the same code at 003Bh-005Ah for the same reason.
K_INTRPT        equ 0038h       ; JP K_ISR
K_SSLOT         equ 0040h       ; the stub, K_SSLOT_LEN bytes
K_SSLOT_LEN     equ 17

; BIOS entry points and work-area variables the kernel calls, reads or
; preserves. The BIOS system area F380h-FFFFh lies above the wall and is
; never written by the resident; these are the addresses it depends on.
B_RDSLT         equ 000Ch       ; A = slot, HL = address -> A; DI on return
B_CALSLT        equ 001Ch       ; IY(h) = slot, IX = address
B_INITXT        equ 006Ch       ; SCREEN 0 with LINL40 columns
B_LINL40        equ 0F3AEh      ; columns SCREEN 0 is initialised with
B_LINLEN        equ 0F3B0h      ; columns in use
B_CRTCNT        equ 0F3B1h      ; rows on screen
B_TXTNAM        equ 0F3B3h      ; SCREEN 0 name table
B_CSRY          equ 0F3DCh      ; cursor row, 1-based
B_JIFFY         equ 0FC9Eh      ; BIOS tick counter, dead after the takeover
B_SCRMOD        equ 0FCAFh      ; current screen mode
B_EXPTBL        equ 0FCC1h      ; per primary slot: 80h if expanded
B_SLTTBL        equ 0FCC5h      ; per primary slot: its subslot register
B_SLTWRK        equ 0FD09h      ; 8 bytes per slot: work-area pointer or data
B_HTIMI         equ 0FD9Fh      ; timer interrupt hook, 5 bytes
B_FCALL         equ 0FFCAh      ; extended BIOS hook, 5 bytes

; Scaffolding shared by the tests and the resident: the tests' buffers, in
; page 2 as DEV_RW demands (page 1 is switched away during a call).
; MAILBOX is 8000h-8003h (tests/m6test.inc).
KT_SCRATCH      equ 8100h       ; 64: _GDLI / _GDRVR blocks
KT_BUF_A        equ 8200h       ; 512: the reference sector, read via Nextor
KT_BUF_B        equ 8400h       ; 512: what the driver returns
KT_BUF_C        equ 8600h       ; 512: patterns
KT_LSTACK       equ 9000h       ; the loader's stack top (page 2: the DOS
                                ; stack sits under DOSHIM and is overwritten)
