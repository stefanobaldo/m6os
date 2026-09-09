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
K_PAGE1         equ K_BASE+15   ; db: what the storage gate put in page 1
                                ;     (k_stgate_enter below); meaningful
                                ;     only inside a storage gate, where
                                ;     k_copy restores page 1 from it
K_API           equ K_BASE+16   ; K_API_N entries of JP, 3 bytes each: what
                                ;     a kernel-side program calls in the
                                ;     resident; the order is fixed and only
                                ;     grows. Entries from API_BLK_RW on are
                                ;     the block layer's and are called under
                                ;     the window and the storage gate only
K_API_N         equ 32
K_SYS           equ K_BASE+112  ; K_SYS_N entries of JP, 3 bytes each: the
                                ;     syscall table, what a process calls
                                ;     (sys.asm); an entry not yet given a
                                ;     syscall returns ENOSYS
K_SYS_N         equ 48
K_REC           equ K_BASE+256  ; the capture record, KREC_SIZE bytes
K_VOL           equ K_BASE+400  ; the volume table (blk.asm): VOL_N rows of
                                ;     VOL_SIZE bytes, filled at boot by the
                                ;     switched part, read by blk_rw
K_BLK_NVOL      equ K_BASE+496  ; db: rows filled
K_BLK_ROOT      equ K_BASE+497  ; db: the row that is the boot volume, /;
                                ;     VOL_NONE when none is
K_BLK_CALLS     equ K_BASE+498  ; dw: driver calls made by the block layer
K_BLK_LASTERR   equ K_BASE+500  ; db: the driver's code from the last one
K_MAP           equ K_BASE+504  ; 4: the segment in each page, as the kernel
                                ;    believes it: from the record at boot,
                                ;    then proc_run's and sys_exit's; the
                                ;    mapper register is never read
K_PROC          equ K_BASE+512  ; the process table (sched.asm): NPROC rows
                                ;     of P_SIZE bytes, one 256-byte page,
                                ;     so a row is K_PROC + (pid << 4)

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
API_SPAWN       equ 12          ; HL image, BC length, A pages -> HL = A =
                                ; the child's pid; CF with the errno in A
API_WAIT        equ 13          ; blocks until a child exits -> H = its pid,
                                ; L = A = its status; CF, E_CHILD
API_YIELD       equ 14          ; the CPU to the next runnable process
API_READ        equ 15          ; A = fd (0), HL = buffer, BC = length ->
                                ; HL = bytes read; blocks until one
; The block layer's entries (blk.asm, ks_blk.asm): called under the window
; and the storage gate — kwin_enter, k_stgate_enter — by the switched part
; of the kernel, or by a test that enters them itself. The ones whose body
; is in the switched part are direct jumps into it.
API_BLK_RW      equ 16          ; A = volume, CF = write, DE:HL = sector,
                                ; B = segment, C = 512-byte slot 0-31;
                                ; CF with the errno in A
API_BLK_DEV_RW  equ 17          ; A = driver, B = device, C = LUN, DE:HL =
                                ; sector -> the storage segment, BUF_SCRATCH
API_K_COPY      equ 18          ; IXH/IXL = source/destination segment, HL/DE
                                ; = their offsets, BC = length
API_BLK_QUERY   equ 19          ; A = driver, B = device, C = LUN, D = BQ_*
                                ; -> ST_INFO of the storage segment
API_BGET        equ 20          ; A = volume, DE:HL = sector -> HL = buffer
API_BWRITE      equ 21          ; HL = buffer
API_BDROP       equ 22          ; A = volume, DE:HL = sector
API_BINVAL      equ 23          ; A = volume
API_BREAD_DIRECT equ 24         ; A = volume, DE:HL = sector, B = segment,
                                ; C = slot
API_BWRITE_DIRECT equ 25        ; the same, writing; bdrop first
API_RTC_READ    equ 26          ; -> HL = FAT date, DE = FAT time

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
SYS_SPAWN       equ 4           ; HL = image (not in page 2), BC = length,
                                ; A = pages 1-3 -> HL = A = the child's pid;
                                ; EINVAL, EAGAIN, ENOMEM
SYS_WAIT        equ 5           ; -> H = pid, L = A = status; ECHILD
SYS_YIELD       equ 6           ; -> nothing
SYS_READ        equ 7           ; A = fd (0), HL = buffer, BC = length ->
                                ; HL = bytes read, 1 to BC; blocks until
                                ; there is one; EBADF, EINVAL
SYS_FORK        equ 8           ; -> HL = A = the child's pid in the parent,
                                ; 0 in the child, whose memory is a copy;
                                ; EPERM, EAGAIN, ENOMEM
SYS_VFORK       equ 9           ; -> the same; the child shares the parent's
                                ; memory and stack and the parent sleeps
                                ; until the child exits; EPERM, EAGAIN
SYS_N           equ 10          ; entries given a syscall so far

    macro sys n
        call    K_SYS+3*n
    endm

SC_PAGESIZE     equ 0           ; 16384
SC_SEGMENTS     equ 1           ; segments in the primary mapper
SC_SEGMENTS_USABLE equ 2        ; the count, or the mem= cap
SC_SEGMENTS_FREE equ 3          ; free now
SC_CHILD_MAX    equ 4           ; processes at once, the kernel's excluded

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
KS_BLK_INIT     equ KS_BASE+6   ; the enumeration and the listing (ks_blk.asm)
KS_CACHE_INIT   equ KS_BASE+9   ; every buffer free
KS_BGET         equ KS_BASE+12  ; the cache's entries, as API_B* say
KS_BWRITE       equ KS_BASE+15
KS_BDROP        equ KS_BASE+18
KS_BINVAL       equ KS_BASE+21
KS_BREAD_DIRECT equ KS_BASE+24
KS_BWRITE_DIRECT equ KS_BASE+27
KS_RTC_READ     equ KS_BASE+30

; The window (kwin.asm) and the storage gate: what is in page 2 and page 1
; while the switched part of the kernel runs. kwin_enter puts the switched
; part into page 2, kwin_leave puts back what K_MAP says belongs there;
; k_stgate_enter puts the storage segment into page 1 and notes it in
; K_PAGE1, k_stgate_leave puts the process's page 1 back. All four use
; AF', which no syscall preserves, instead of the stack. A program that
; calls the block layer's entries enters and leaves both around the calls.
    macro kwin_enter                    ; the switched part into page 2
        ex      af,af'
        ld      a,(K_KSEG)
        out     (0FEh),a
        ex      af,af'
    endm

    macro kwin_leave                    ; what belongs in page 2, back
        ex      af,af'
        ld      a,(K_MAP+2)
        out     (0FEh),a
        ex      af,af'
    endm

    macro k_stgate_enter                ; the storage segment into page 1
        ex      af,af'
        ld      a,(K_REC+KR_SEG64K+2)
        ld      (K_PAGE1),a
        out     (0FDh),a
        ex      af,af'
    endm

    macro k_stgate_leave                ; the process's page 1, back
        ex      af,af'
        ld      a,(K_MAP+1)
        out     (0FDh),a
        ex      af,af'
    endm

; A process (proc.asm, sched.asm): what it sees in page 0, and its row in
; the process table. Process 0 is the kernel's own thread; pids 1 to
; NPROC-1 are processes, and a pid is the index of its row.
P0_EXIT         equ 0060h       ; xor a; jp K_SYS+3*SYS_EXIT — where a
                                ; program's final ret lands, and jp 0's
P0_PROG         equ 0100h       ; where the program starts
P0_FRAME        equ 24          ; bytes the kernel may use on a process's
                                ; stack at any instant: an interrupt's
                                ; return address and the saved context
NPROC           equ 16
P_STATE         equ 0           ; PS_*
P_SP            equ 1           ; 2: the stack pointer while not running;
                                ;    the saved context is on that stack
P_PID           equ 3           ; the row's index; the owner in the allocator
P_PPID          equ 4           ; the parent's pid, or PP_NONE
P_NPAGES        equ 5           ; pages, 1-3; 0 for process 0
P_SEG           equ 6           ; 3: the segment in each of pages 0-2
P_STATUS        equ 9           ; the exit status
P_NEXT          equ 10          ; low byte of the next row in the ring of
                                ; runnable rows (sched.asm); meaningful
                                ; only while the row is PS_RUN
P_VPC           equ 11          ; 2: a vfork parent's return address, kept
                                ;    here because the child's pushes
                                ;    overwrite it on the shared stack
P_SIZE          equ 16
PS_FREE         equ 0           ; the row is nobody's
PS_RUN          equ 1           ; runnable, or running
PS_WAIT         equ 2           ; blocked in wait
PS_ZOMBIE       equ 3           ; exited; the status waits for the parent
PS_KBD          equ 4           ; blocked in read, waiting for a key
PS_VFORK        equ 5           ; blocked in vfork, until the child exits
PP_NONE         equ 0FFh        ; a parent that will never wait

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
KR_VDPREG       equ 61          ; 10: VDP registers 0-9 as the previous
                                ;     system's shadows had them; the
                                ;     console keeps R#7-R#9 and finds the
                                ;     font through R#4
KR_KBDTYPE      equ 71          ; the ROM's keyboard type byte (002Ch),
                                ; report only
KR_NDRV         equ 72          ; Nextor drivers found, 0-4; a fifth is
                                ; counted and not stored
KR_DRVS         equ 73          ; 4 x (slot, bank): the device-based Nextor
                                ; drivers with a valid header, in _GDRVR
                                ; order; the block layer's driver index
                                ; 0-3 is the position here
KREC_SIZE       equ 81

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

; The block layer (blk.asm, ks_blk.asm). Sectors are 512 bytes; a sector
; number is 32 bits and travels in DE:HL, DE high; a transfer target is a
; segment and a 512-byte slot in it, 0-31.
BLK_PER_CALL    equ 1           ; sectors per driver call: one keeps the
                                ; interrupt-disabled region inside a frame
VOL_N           equ 8           ; volumes the table holds
VOL_SIZE        equ 12
V_DRV           equ 0           ; driver index 0-3; FFh = the row is free
V_DEV           equ 1           ; device 1-7
V_LUN           equ 2           ; LUN 1-7
V_FLAGS         equ 3           ; VF_*, as LUN_INFO gives them
V_FIRST         equ 4           ; 4: first device sector
V_COUNT         equ 8           ; 4: sectors
VF_REMOVABLE    equ 1
VF_RO           equ 2
VOL_NONE        equ 0FFh        ; blk_root when no volume is the boot one
BQ_DEVINFO      equ 0           ; blk_query: DEV_INFO basic, 2 bytes
BQ_LUNINFO      equ 1           ; LUN_INFO, 12 bytes
BQ_DRVNAME      equ 2           ; DRV_NAME, 32 bytes

; The storage segment: the boot segment of page 2 (KR_SEG64K+2), the
; kernel's, addressed as (segment, offset) — the switched part sees it at
; 4000h+offset under the storage gate, process 0 at 8000h+offset.
ST_TESTS        equ 0000h       ; 2K: the mailbox and the tests' buffers,
                                ; written by the loader under Nextor and
                                ; read after the takeover; never cleared
ST_HDR          equ 0800h       ; the cache headers, BUF_N x 8
ST_INFO         equ 08C0h       ; 64: what blk_query returns; the copy of
                                ; the primary entries during the walk
ST_VARS         equ 0900h       ; 128: the switched part's variables (it
                                ; keeps none of its own: it may be ROM)
ST_RESERVED     equ 0980h       ; to 0FFFh: the open-file table, the mount
                                ; table, the exec argument area — later
ST_BUF          equ 1000h       ; BUF_N sector buffers of 512
BUF_N           equ 24
BUF_SCRATCH     equ 23          ; the enumeration's buffer at boot
H_VOL           equ 0           ; a header: the volume; FFh = free
H_SEC           equ 1           ; 4: the sector
H_AGE           equ 5           ; the clock's value at the last touch
H_SIZE          equ 8
SV_CLOCK        equ ST_VARS+0   ; the cache's clock
SV_TOTAL        equ ST_VARS+1   ; 4: the LUN's sectors, 0 = unknown
SV_LFLAGS       equ ST_VARS+5   ; the LUN's flags, VF_*
SV_EXT          equ ST_VARS+6   ; 4: the extended partition's first sector
SV_EXTEND       equ ST_VARS+10  ; 4: its end (first + count)
SV_EBR          equ ST_VARS+14  ; 4: the current EBR's sector
SV_NLOG         equ ST_VARS+18  ; logical partitions seen in this chain
SV_PRI          equ ST_VARS+19  ; the primary entry being walked, 1-4
SV_CAND         equ ST_VARS+20  ; 4: the candidate's first sector
SV_CCOUNT       equ ST_VARS+24  ; 4: its sectors
SV_CTYPE        equ ST_VARS+28  ; its type byte
SV_FOUND        equ ST_VARS+29  ; candidates found on this LUN
SV_DRV          equ ST_VARS+30  ; the driver, device and LUN being walked
SV_DEV          equ ST_VARS+31
SV_LUN          equ ST_VARS+32
SV_NDEV         equ ST_VARS+33  ; volumes found on this device
SV_NLUN         equ ST_VARS+34  ; LUNs the device has
SV_LINK         equ ST_VARS+35  ; 4: the next EBR, relative to SV_EXT
SV_LTYPE        equ ST_VARS+39  ; the link entry's type
SV_PKIND        equ ST_VARS+40  ; PK_*: how the candidate is labelled
SV_NDRV         equ ST_VARS+41  ; drivers to walk
SV_FULL         equ ST_VARS+42  ; the "more volumes" line was printed
SV_NAMELEN      equ ST_VARS+43  ; the driver's name without its padding
SV_RTC          equ ST_VARS+44  ; 13: the RTC's registers as read
SV_NAME         equ ST_VARS+64  ; 32: the driver's name
PK_PRIMARY      equ 0
PK_LOGICAL      equ 1
PK_SUPER        equ 2

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
B_RG0SAV        equ 0F3DFh      ; 8: the BIOS's copy of VDP R#0-R#7
B_RG8SAV        equ 0FFE7h      ; 16: the same for R#8-R#23

; The console (con.asm, vdp_t2.asm): TEXT2, 80 x 24, on the kernel's own
; VRAM layout. The name table is where the BIOS keeps SCREEN 0's, so the
; lines the loader printed survive the takeover.
CON_COLS        equ 80
CON_ROWS        equ 24
V_NAME          equ 0000h       ; name table, 80 x 24 = 1920 bytes
V_BLINK         equ 0800h       ; blink table, 10 x 24 = 240 bytes: the
                                ; cursor's bit and nothing else
V_PAT           equ 1000h       ; pattern table, the font, 2048 bytes

; The keyboard (kbd.asm): the PPI, and the queue of events between the
; interrupt handler and read.
PPI_A           equ 0A8h        ; the primary slot register
PPI_B           equ 0A9h        ; the selected row's eight columns, 0 = down
PPI_C           equ 0AAh        ; bits 0-3 the row, bit 6 the CAPS LED (0 = lit)
KBD_ROWS        equ 11
KBD_RING_N      equ 16          ; events the queue holds, two bytes each

; Scaffolding shared by the tests and the resident: the tests' buffers, in
; page 2 as DEV_RW demands (page 1 is switched away during a call).
; MAILBOX is 8000h-8003h (tests/m6test.inc).
KT_SCRATCH      equ 8100h       ; 64: _GDLI / _GDRVR blocks
KT_BUF_A        equ 8200h       ; 512: the reference sector, read via Nextor
KT_BUF_B        equ 8400h       ; 512: what the driver returns
KT_BUF_C        equ 8600h       ; 512: patterns
KT_LSTACK       equ 9000h       ; the loader's stack top (page 2: the DOS
                                ; stack sits under DOSHIM and is overwritten)
