; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
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
K_KBDLAST       equ K_BASE+392  ; dw: -> the keyboard scan's baseline, 11
                                ;     bytes (kbd.asm)
K_LDSTATE       equ K_BASE+394  ; dw: -> the terminal's line state, laid out
                                ;     as LD_* (tty.asm)
K_CONCUR        equ K_BASE+396  ; dw: -> the console's cursor: the row, then
                                ;     the column (con.asm)
K_DOSTMPL       equ K_BASE+398  ; dw: -> the hinge's two stubs, K_HINGE_STUBS
                                ;     bytes, the image dosenter copies (dos.asm)
                                ; The four name resident objects the switched
                                ; part reaches by address, which the header
                                ; otherwise does not give it. The record's
                                ; room to grow ends at K_KBDLAST.
K_VOL           equ K_BASE+400  ; the volume table (blk.asm): VOL_N rows of
                                ;     VOL_SIZE bytes, filled at boot by the
                                ;     switched part, read by blk_rw
K_BLK_NVOL      equ K_BASE+496  ; db: rows filled
K_BLK_ROOT      equ K_BASE+497  ; db: the row that is the boot volume, /;
                                ;     VOL_NONE when none is
K_BLK_CALLS     equ K_BASE+498  ; dw: driver calls made by the block layer
K_BLK_LASTERR   equ K_BASE+500  ; db: the driver's code from the last one
K_DOSPID        equ K_BASE+501  ; db: the pid of the legacy process (dos.asm),
                                ;     0 when no .COM program is running
K_DOSP0         equ K_BASE+502  ; db: that process's original page-0 segment
K_NRUN          equ K_BASE+503  ; db: rows in PS_RUN, the current one included
                                ;     (sched.asm); the tick with one runnable
                                ;     process costs a compare of it
K_MAP           equ K_BASE+504  ; 4: the segment in each page, as the kernel
                                ;    believes it: from the record at boot,
                                ;    then proc_run's and sys_exit's; the
                                ;    mapper register is never read
K_CUR           equ K_BASE+508  ; dw: the current process's row (sched.asm)
K_PID           equ K_BASE+510  ; dw: its pid; the high byte stays 0
K_PROC          equ K_BASE+512  ; the process table (sched.asm): NPROC rows
                                ;     of P_SIZE bytes, one 256-byte page,
                                ;     so a row is K_PROC + (pid << 4)
K_FD            equ K_BASE+768  ; the descriptor table: NPROC rows of NOFILE
                                ;     bytes, a row at K_FD + (pid << 3); a
                                ;     byte is FD_NONE, FD_CON, FD_KBD, a
                                ;     pipe end (FD_PIPE_R/W + n) or an index
                                ;     into the open-file table (ST_OFT)
K_PX            equ K_BASE+896  ; the per-process extension table: NPROC
                                ;     rows of PX_SIZE bytes, a row at
                                ;     K_PX + (pid << 3) — what the 16-byte
                                ;     process row has no room for
K_PIPEBUF       equ K_BASE+1024 ; NPIPE pipe buffers of 256 bytes, 256-
                                ;     aligned: byte i of pipe n is at
                                ;     (high K_PIPEBUF + n) : i (pipe.asm)
K_API2          equ K_BASE+2048 ; API2_N entries of JP, 3 bytes each: what
                                ;     the switched part calls in the resident
                                ;     beyond K_API, which is full; the same
                                ;     rules — the order is fixed and only
                                ;     grows. The image's code starts after it
API2_N          equ 12
NOFILE          equ 8
FD_NONE         equ 0FFh
FD_CON          equ 0FEh        ; the console: write
FD_KBD          equ 0FDh        ; the keyboard: read
FD_PIPE_R       equ 0E0h        ; + n: the read end of pipe n (pipe.asm)
FD_PIPE_W       equ 0F0h        ; + n: its write end
NPIPE           equ 4           ; pipes the kernel holds
PIPE_MAX        equ 256         ; bytes a pipe holds: its whole buffer
PX_SIZE         equ 8
PX_WCHAN        equ 0           ; the pipe a PS_PIPE row waits on; FFh none
PX_WAKE         equ 1           ; 2: the K_TICKS a PS_SLEEP row wakes at
PX_SIGIGN       equ 3           ; signals ignored: SIGIGN_* bits (sig.asm)
PX_SIGPEND      equ 4           ; a signal pending, its number; 0 none
                                ; 5-7 spare
PI_SIZE         equ 8           ; a pipe's row (pipe.asm): free when both
PI_HEAD         equ 0           ; counts are 0. head = tail means empty,
PI_TAIL         equ 1           ; or full when PI_FULL says so: the whole
PI_FULL         equ 2           ; buffer is usable
PI_READERS      equ 3
PI_WRITERS      equ 4
PI_RWAIT        equ 5           ; the pid blocked reading it, FFh none
PI_WWAIT        equ 6           ; the pid blocked writing it, FFh none
PI_MANY         equ 7           ; a second waiter on an end: a wake walks
                                ; the process table instead

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
API_EXEC_FINISH equ 27          ; exec's resident tail (proc.asm): the new
                                ; image's frame and row, then into it; never
                                ; returns. Under the window and the gate,
                                ; with ST_VFS's VX_* filled
API_BFLUSH      equ 28          ; every dirty buffer written, a FAT sector to
                                ; every copy; CF with the first errno met
API_BZERO       equ 29          ; A = volume, DE:HL = sector -> HL = a buffer
                                ; of zeros for it, nothing read
API_CON_WRITE   equ 30          ; HL -> bytes, BC = how many: to the console
API_ROW_READ    equ 31          ; A = a row -> HL -> its CON_COLS cells

; k_call n — call the resident through the jump table.
    macro k_call n
        call    K_API+3*n
    endm
    macro k_call2 n
        call    K_API2+3*n
    endm

; The second table's entries (kernel.asm). Contracts are the routines' own.
API2_MEM_OWN    equ 0           ; A = segment, B = the new owner (mem.asm)
API2_MEM_RELEASE equ 1          ; A = a segment reserved at boot: freed
API2_MEM_OWNER  equ 2           ; A = segment -> A = its owner byte
API2_CON_INIT   equ 3           ; the console up (con.asm)
API2_KBD_INIT   equ 4           ; the keyboard's baseline (kbd.asm)
API2_VDP_CLEAR_ROWS equ 5       ; A = first row, B = count: spaces
API2_PX_ROW     equ 6           ; A = pid -> HL -> its extension row
API2_SIG_SEND   equ 7           ; HL = a row, C = a signal; under di
API2_SIG_BIT    equ 8           ; A = a signal -> A = its PX_SIGIGN bit; CF
API2_SIG_STUB   equ 9           ; the current process dies of its signal
API2_CON_CURSOR equ 10          ; -> L = the console's row, H = its column
API2_DOS_TAIL   equ 11          ; dosenter's crossing: the pages back, the
                                ; hinge's second stub; never returns

; The syscalls (sys.asm, proc.asm, kseg.asm) and their table indices. A
; process calls K_SYS+3*n. Arguments in A, HL, DE, BC as each syscall says;
; the result in HL (and A when it fits a byte); CF set on error with the
; errno in A. Nothing the syscall does not return is preserved: BC, DE, IX,
; IY and the alternate set are undefined afterwards.
SYS_EXIT        equ 0           ; A = status; does not return
SYS_WRITE       equ 1           ; A = fd, HL = buffer, BC = length -> HL =
                                ; bytes written; the console, or a file
                                ; open for writing (ks_vfsw.asm): EBADF,
                                ; EISDIR, ENOSPC, EIO, EROFS
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
; The filesystem's (ks_vfs.asm, ks_exec.asm), every one switched, under the
; storage gate. A path is a 0-terminated string of at most PATH_MAX bytes,
; components separated by '/', relative to the process's current directory
; unless it begins with '/'.
SYS_OPEN        equ 10          ; HL = path, A = O_* flags -> HL = A = fd;
                                ; ENOENT, ENOTDIR, ENAMETOOLONG, EMFILE,
                                ; ENFILE, EINVAL, EISDIR, EACCES, EBUSY,
                                ; ENOSPC, EIO, EROFS
SYS_CLOSE       equ 11          ; A = fd; EBADF
SYS_LSEEK       equ 12          ; A = fd, DE:HL = offset, B = SEEK_* ->
                                ; DE:HL = the position (the one syscall
                                ; whose result is 32 bits); EBADF, EINVAL
SYS_STAT        equ 13          ; HL = path, DE = a DIRENT_SIZE buffer;
                                ; ENOENT, ENOTDIR, ENAMETOOLONG, EIO
SYS_READDIR     equ 14          ; A = fd (a directory), HL = a DIRENT_SIZE
                                ; buffer -> HL = 1 (an entry), 0 (the end);
                                ; EBADF, ENOTDIR, EIO
SYS_CHDIR       equ 15          ; HL = path (a directory); ENOENT, ENOTDIR,
                                ; ENAMETOOLONG, EIO
SYS_EXEC        equ 16          ; HL = path, DE = argv (a 0-terminated vector
                                ; of pointers; 0 = none): the process's image
                                ; is replaced and does not return; ENOENT,
                                ; ENOTDIR, EISDIR, ENOEXEC, E2BIG, ENOMEM,
                                ; EIO, EPERM (process 0)
SYS_UNLINK      equ 17          ; HL = path (a file): removed; ENOENT,
                                ; ENOTDIR, EISDIR, EACCES, EBUSY, EIO, EROFS
SYS_MKDIR       equ 18          ; HL = path: a directory made; ENOENT (the
                                ; parent), ENOTDIR, EEXIST, EINVAL, ENOSPC,
                                ; EIO, EROFS
SYS_RMDIR       equ 19          ; HL = path (an empty directory): removed;
                                ; ENOENT, ENOTDIR, ENOTEMPTY, EBUSY, EINVAL,
                                ; EIO, EROFS
SYS_RENAME      equ 20          ; HL = old path, DE = new path, on one
                                ; volume; a file replaces a file; ENOENT,
                                ; ENOTDIR, EXDEV, EEXIST, EINVAL, EACCES,
                                ; EBUSY, ENOSPC, EIO, EROFS
; The pipeline path (pipe.asm, proc.asm, px.asm) and the small calls.
SYS_PIPE        equ 21          ; -> L = the read end, H = the write end;
                                ; EMFILE, ENFILE
SYS_SPAWNV      equ 22          ; HL = path, DE = argv (0 = none), BC -> 3
                                ; bytes: the caller's descriptor that is
                                ; the child's 0, 1, 2, FFh = the caller's
                                ; own; A = SIGIGN_* bits of the signals the
                                ; child takes by default though the caller
                                ; ignores them (0 = all as the caller's)
                                ; -> HL = A = the child's pid; exec's
                                ; errors but EPERM, plus EBADF, EAGAIN
SYS_WAITPID     equ 23          ; A = pid (0 = any child), B = WNOHANG or
                                ; 0 -> H = pid, L = A = status; HL = 0 with
                                ; WNOHANG and nothing exited; ECHILD
SYS_SLEEP       equ 24          ; HL = ticks -> HL = 0, after them
SYS_PROCINFO    equ 25          ; A = pid, HL = a PROCINFO_SIZE buffer;
                                ; EINVAL, ESRCH
SYS_GETCWD      equ 26          ; HL = buffer, BC = its size -> HL = the
                                ; length; ENAMETOOLONG, EIO
SYS_TIME        equ 27          ; -> HL = FAT date, DE = FAT time
SYS_CHMOD       equ 28          ; HL = path, A = DA_RDONLY|DA_HIDDEN|
                                ; DA_SYSTEM|DA_ARCHIVE; EINVAL, ENOENT,
                                ; ENOTDIR, EACCES, EROFS, EIO
; The terminal and signals (tty.asm, sig.asm).
SYS_TTYMODE     equ 29          ; A = TTY_CANON, TTY_RAW or TTY_RECALL ->
                                ; L = the mode that was; EINVAL. The mode
                                ; is the terminal's, not the process's
SYS_KILL        equ 30          ; A = pid, B = a signal: it terminates the
                                ; process, or is ignored; EPERM (pid 0),
                                ; EINVAL (pid >= NPROC, a bad signal),
                                ; ESRCH (a free row)
SYS_SIGNAL      equ 31          ; A = a signal, B = SIG_DFL or SIG_IGN ->
                                ; L = the action that was; EINVAL
SYS_TTYLINE     equ 32          ; HL = a line, BC = its length, 0 to
                                ; TTY_LINE-1: the line being edited
                                ; replaced by it, or one opened; EINVAL,
                                ; EFAULT
; The legacy subsystem (dos.asm; src/leg/ is the layer, src/bin/dos.asm the
; program that sets a .COM up): a process maps segments of its own into
; pages 1 and 2, fills one with the layer and a copy of the kernel's page
; 3, and crosses into it.
SYS_DOSENTER    equ 33          ; A = the legacy page-3 segment, the
                                ; caller's, filled as src/leg/leg.asm
                                ; expects, pages 1 and 2 mapped by segmap
                                ; to the program's: the caller becomes the
                                ; program and the call does not return;
                                ; EPERM (process 0), EBUSY (a .COM runs
                                ; already), EINVAL (not the caller's
                                ; segment)
SYS_SEGALLOC    equ 34          ; -> HL = A = a segment owned by the
                                ; caller, freed at its exit; ENOMEM; EPERM
                                ; (process 0)
SYS_SEGFREE     equ 35          ; A = a segment of the caller's, not one
                                ; of its pages: freed; EINVAL
SYS_SEGMAP      equ 36          ; A = a page, 1 or 2; B = a segment of the
                                ; caller's: mapped there, and kept there
                                ; across syscalls and switches; EINVAL
                                ; (the page, or not the caller's segment)
SYS_STATFS      equ 37          ; A = a volume 0-7, HL = a 32-byte buffer,
                                ; B = 0, or 1 to count the free clusters
                                ; too (a walk of the table): the block
                                ; SF_* describes; ENODEV, EFAULT, EIO
SYS_UTIME       equ 38          ; HL = path, DE = a FAT date, BC = a FAT
                                ; time: the entry's modification stamp;
                                ; ENOENT, ENOTDIR, ENAMETOOLONG, EACCES (a
                                ; root, /mnt), EROFS, EIO
SYS_STATL       equ 39          ; HL = path, DE = a DIRENT_SIZE buffer: as
                                ; stat, in the short form (DE_LOC)
SYS_N           equ 40          ; entries given a syscall so far
WNOHANG         equ 1           ; waitpid: do not block
PROCINFO_SIZE   equ P_SIZE+PX_SIZE ; the row, then the extension row

; Signals (sig.asm). Four, terminate or ignore, never a handler; a process
; a signal ended reports 128 + the signal through waitpid. The numbers are
; Unix's; SIGKILL cannot be ignored.
SIGINT          equ 2           ; ^C or STOP from the keyboard, or kill
SIGKILL         equ 9           ; kill only, never ignorable
SIGPIPE         equ 13          ; a write to a pipe with no reader
SIGTERM         equ 15          ; kill's default ask to end
SIGIGN_INT      equ 1           ; the PX_SIGIGN bit of each ignorable signal
SIGIGN_PIPE     equ 2
SIGIGN_TERM     equ 4
SIG_DFL         equ 0           ; signal's action: terminate
SIG_IGN         equ 1           ;   or ignore
SF_INT          equ 1           ; k_sigflag: a ^C is to be broadcast
SF_PEND         equ 2           ;   the current process owes a signal
SF_PLANT        equ 4           ;   some process owes one not yet planted:
                                ;   sched_load looks before it loads

; The line discipline (tty.asm). Canonical by default: read on the keyboard
; returns edited lines; raw is byte for byte, no echo, as 2.4 left it.
TTY_CANON       equ 0
TTY_RAW         equ 1
TTY_RECALL      equ 2           ; canonical, and UP or DOWN ends the read
                                ; with its byte and an LF, the line kept
                                ; open for the next read or ttyline
TTY_LINE        equ 128         ; bytes of the terminal's line buffer
; The line's state (tty.asm), as the editor in the switched part reaches
; it through IX.
LD_LEN          equ 0           ; bytes in the line
LD_POS          equ 1           ; of them, delivered already
LD_EOF          equ 2           ; a ^D on an empty line is owed
LD_COL          equ 3           ; the column the line started at
LD_CUR          equ 4           ; the cursor: an index, 0 to the length
LD_OPEN         equ 5           ; the line is open: the next read goes on
                                ; with it instead of starting one
LD_MODE         equ 6           ; the terminal's mode: TTY_*
LD_BUF          equ 7           ; the line, TTY_LINE bytes

O_RDONLY        equ 0           ; open's flags: the access mode in bits 0-1
O_WRONLY        equ 1           ; (3 is EINVAL), then
O_RDWR          equ 2
O_APPEND        equ 08h         ; every write at the end
O_CREAT         equ 40h         ; create the file when it is not there
O_TRUNC         equ 80h         ; with a writable mode: empty it first
O_SHORT         equ 10h         ; a directory: readdir fills the short form
SEEK_SET        equ 0           ; lseek's whence: from the start,
SEEK_CUR        equ 1           ; the position,
SEEK_END        equ 2           ; the end
PATH_MAX        equ 256         ; bytes of a path, its terminator included
NAME_MAX        equ 255         ; bytes of one component: VFAT's limit

; What stat and readdir return: DIRENT_SIZE bytes in the caller's buffer.
DIRENT_SIZE     equ 265
DE_NAME         equ 0           ; NAME_MAX+1: the name, 0-terminated — the
                                ; long name when the entry has one, else
                                ; the short name as stored, lower-cased
                                ; where its case bits say so
DE_ATTR         equ 256         ; the FAT attribute byte: DA_*
DE_SIZE         equ 257         ; 4: bytes; 0 for a directory
DE_MTIME        equ 261         ; 4: the FAT date word, then the time word
; The short form — statl, and readdir on a descriptor opened with
; O_SHORT: DE_NAME holds the 8.3 alias as stored, upper case, with its
; dot, 0-terminated, at most 13 bytes ("." and ".." as they are; a root
; its letter, /mnt "mnt", a directory known by its cluster "."), then the
; entry's locator; the rest of the record as above. getcwd with bit 15 of
; the size set writes the components the same way.
DE_LOC          equ 13          ; 8: the locator, DL_*
DL_VOL          equ 0           ; the volume (VOL_NONE: /mnt)
DL_CLUS         equ 1           ; 2: the first cluster (a directory's own)
DL_SEC          equ 3           ; 4: the entry's sector, 0 for a root
DL_IDX          equ 7           ;    and its index
DL_SIZE         equ 8
; A directory locator, what chdir takes with HL = 0 and DE -> it: the
; volume, then the cluster — P_CWD's own three bytes.
LOC_VOL         equ 0
LOC_CLUS        equ 1
LOC_SIZE        equ 3
; What statfs fills: the MSX-DOS 2 _DPARM block, 32 bytes.
SF_DRIVE        equ 0           ; the volume + 1
SF_SECSIZE      equ 1           ; 2: 512
SF_SPC          equ 3           ; sectors per cluster
SF_RESERVED     equ 4           ; 2: sectors before the first FAT
SF_NFATS        equ 6
SF_ROOTENT      equ 7           ; 2: root directory entries
SF_TOTAL        equ 9           ; 2: the volume's sectors, 0 above 65535
SF_MEDIA        equ 11          ; F8h
SF_FATSZ        equ 12          ; sectors per FAT, 0 above 255
SF_ROOTSEC      equ 13          ; 2: the root directory's first sector
SF_DATASEC      equ 15          ; 2: the first data sector
SF_MAXCLUS      equ 17          ; 2: the highest cluster number
SF_DIRTY        equ 19          ; 0
SF_VOLID        equ 20          ; 4: -1, not read
SF_FREE         equ 24          ; 2: free clusters, with B = 1; else 0
SF_SIZE         equ 32          ; 26-31 zero
DA_RDONLY       equ 01h
DA_HIDDEN       equ 02h
DA_SYSTEM       equ 04h
DA_LABEL        equ 08h         ; a volume label, or with the three above
                                ; an LFN entry: never a file
DA_DIR          equ 10h
DA_ARCHIVE      equ 20h

; An executable file: loaded at P0_PROG, it begins with a jump over a
; six-byte header, and the kernel refuses a file without the signature.
XH_JR           equ 0           ; 2: jr start
XH_SIGN         equ 2           ; 2: "m6"
XH_PAGES        equ 4           ; pages the program wants, 1-3
XH_FLAGS        equ 5           ; 0
XH_SIZE         equ 6
ARGV_MAX        equ 512         ; bytes of an argument block: the pointers
                                ; and the strings

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
E_XDEV          equ 18
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
E_NOTEMPTY      equ 39          ; Linux's number, as ENOSYS
E_NAMETOOLONG   equ 63          ; Linux's number, as ENOSYS

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
KS_BOOT         equ KS_BASE+33  ; the scheduler's first row and the boot
                                ; pages released (ks_boot.asm), once
; The table's first part ends before the interrupt entry at KS_BASE+0038h;
; it continues after the subslot stub, from KS_TABLE2.
KS_TABLE2       equ KS_BASE+K_SSLOT+K_SSLOT_LEN
KS_READ         equ KS_TABLE2+0 ; the filesystem's syscalls (ks_vfs.asm,
KS_OPEN         equ KS_TABLE2+3 ; ks_exec.asm), entered through k_sw_s
KS_CLOSE        equ KS_TABLE2+6
KS_LSEEK        equ KS_TABLE2+9
KS_STAT         equ KS_TABLE2+12
KS_READDIR      equ KS_TABLE2+15
KS_CHDIR        equ KS_TABLE2+18
KS_EXEC         equ KS_TABLE2+21
KS_WRITE        equ KS_TABLE2+24 ; the write side (ks_vfsw.asm)
KS_UNLINK       equ KS_TABLE2+27
KS_MKDIR        equ KS_TABLE2+30
KS_RMDIR        equ KS_TABLE2+33
KS_RENAME       equ KS_TABLE2+36
KS_BFLUSH       equ KS_TABLE2+39 ; the cache's write side (ks_blk.asm)
KS_BZERO        equ KS_TABLE2+42
KS_SPAWNV       equ KS_TABLE2+45 ; (ks_exec.asm)
KS_GETCWD       equ KS_TABLE2+48 ; (ks_vfs.asm)
KS_CHMOD        equ KS_TABLE2+51 ; (ks_vfsw.asm)
KS_TTY_KEY      equ KS_TABLE2+54 ; the line editor: A = a key (ks_tty.asm)
KS_TTY_SET      equ KS_TABLE2+57 ; the line replaced: echoed, cursor at its end
KS_DOS_CHECK    equ KS_TABLE2+60 ; an MSX-DOS program's exit (ks_sys.asm):
                                ; IX -> kbd_last, IY -> con_row; A kept
KS_PROCINFO     equ KS_TABLE2+63 ; the cold syscalls, through k_sw_s
KS_SEGALLOC     equ KS_TABLE2+66
KS_SEGFREE      equ KS_TABLE2+69
KS_SEGMAP       equ KS_TABLE2+72
KS_KILL         equ KS_TABLE2+75
KS_SIGNAL       equ KS_TABLE2+78
KS_DOSENTER     equ KS_TABLE2+81 ; never returns: API2_DOS_TAIL
KS_TTYMODE      equ KS_TABLE2+84
KS_TTYLINE      equ KS_TABLE2+87
KS_STATFS       equ KS_TABLE2+90 ; (ks_vfs.asm)
KS_UTIME        equ KS_TABLE2+93 ; (ks_vfsw.asm)
KS_STATL        equ KS_TABLE2+96 ; (ks_vfs.asm)

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

; kwin_call target — a kernel-side call into the switched part, on the
; caller's own stack, which is in page 3. Every register reaches the callee
; and comes back as it leaves them.
    macro kwin_call target
        kwin_enter
        call    target
        kwin_leave
    endm

; kwin_call_s target — kwin_call with the storage gate: what k_main uses
; to enter the block layer's boot code.
    macro kwin_call_s target
        kwin_enter
        k_stgate_enter
        call    target
        k_stgate_leave
        kwin_leave
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
P0_TOP          equ 4000h-ARGV_MAX-P0_FRAME ; where a one-page program's
                                ; memory ends: the argument block and the
                                ; frame sit above it, under the page's top
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
P_CWD           equ 13          ; 3: the current directory — the volume,
                                ;    then a cluster (0 = the volume's root);
                                ;    VOL_NONE as the volume is /mnt
P_SIZE          equ 16
PS_FREE         equ 0           ; the row is nobody's
PS_RUN          equ 1           ; runnable, or running
PS_WAIT         equ 2           ; blocked in wait
PS_ZOMBIE       equ 3           ; exited; the status waits for the parent
PS_KBD          equ 4           ; blocked in read, waiting for a key
PS_VFORK        equ 5           ; blocked in vfork, until the child exits
PS_PIPE         equ 6           ; blocked on a pipe: PX_WCHAN says which
PS_SLEEP        equ 7           ; blocked in sleep, until PX_WAKE
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
; segment and a 256-byte slot in it, 0-62 (BLK_SLOTS): the sector lands at
; slot * 256 and must not cross the page, so that a whole sector goes from
; the driver into a program's page at any 256-byte boundary — P0_PROG
; included — with no copy.
BLK_PER_CALL    equ 1           ; sectors per driver call: one keeps the
                                ; interrupt-disabled region inside a frame
BLK_SLOTS       equ 63          ; slots a segment has: 0-62
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
ST_MNT          equ 0980h       ; the mount table: MNT_N rows of MNT_SIZE,
                                ; row i describing volume i of K_VOL
ST_OFT          equ 0A80h       ; the open-file table: OFT_N rows of OFT_SIZE
ST_LNAME        equ 0CC0h       ; NAME_MAX+1: a name, 0-terminated — read
                                ; from its chain, or built for readdir and
                                ; stat to hand out
ST_VFS          equ 0DC0h       ; 320: the filesystem's variables (VV_*, VX_*)
ST_VFSW         equ 0F00h       ; 256: the write side's variables (VW_*)
ST_PATH         equ 1000h       ; PATH_MAX: the path a syscall copies in
ST_PATH2        equ 1100h       ; PATH_MAX: rename's second path
ST_ARGV         equ 1200h       ; ARGV_MAX: exec's argument block, gathered
                                ; before the image is overwritten
ST_BUF          equ 1400h       ; BUF_N sector buffers of 512
BUF_N           equ 22
BUF_SCRATCH     equ 21          ; the enumeration's buffer at boot
H_VOL           equ 0           ; a header: the volume; FFh = free
H_SEC           equ 1           ; 4: the sector
H_AGE           equ 5           ; the clock's value at the last touch
H_FLAGS         equ 6           ; HF_*
H_SIZE          equ 8
HF_DIRTY        equ 1           ; newer than the disk: written by bflush
                                ; before the syscall returns, never evicted
HF_FAT          equ 2           ; a FAT sector: bflush writes every copy
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
SV_FERR         equ ST_VARS+96  ; bflush: the first errno met, 0 = none
SV_FHDR         equ ST_VARS+97  ; 2: the header being flushed
SV_FN           equ ST_VARS+99  ;    copies still to write
SV_FSTEP        equ ST_VARS+100 ; 2: sectors between two FAT copies
SV_FSEC         equ ST_VARS+102 ; 4: the sector being written
SV_FKEY         equ ST_VARS+106 ; 2: bc_find: the sector's high word
SV_LAST         equ ST_VARS+108 ; 2: the header of bc_find's last hit
PK_PRIMARY      equ 0
PK_LOGICAL      equ 1
PK_SUPER        equ 2

; The filesystem (ks_fat.asm, ks_vfs.asm, ks_exec.asm): FAT12 and FAT16,
; read only. A mount row is filled at boot from the boot sector the
; enumeration validates; every sector in it is relative to the volume, so
; blk_rw's bounds check stands between a chain and the neighbouring
; partition.
MNT_N           equ VOL_N
MNT_SIZE        equ 32
M_FLAGS         equ 0           ; MF_*
M_SPC           equ 1           ; sectors per cluster, 1-128
M_SPCSH         equ 2           ; log2 of it
M_NFATS         equ 3
M_FATSZ         equ 4           ; 2: sectors per FAT
M_FAT           equ 6           ; 4: the first FAT's first sector
M_ROOT          equ 10          ; 4: the root directory's first sector
M_ROOTN         equ 14          ; 2: its sectors
M_DATA          equ 16          ; 4: the sector of cluster 2
M_NCLUS         equ 20          ; 2: data clusters, at most 65524
M_HINT          equ 22          ; 2: where a new file's first cluster is
                                ;    looked for; 2 at mount
                                ; 24-31 spare
MF_FAT16        equ 1           ; else FAT12

OFT_N           equ 24
OFT_SIZE        equ 24
OF_VOL          equ 0           ; the volume; VOL_NONE = the row is free
OF_REFS         equ 1           ; descriptors pointing here, every process
OF_FLAGS        equ 2           ; OFF_*
OF_FIRST        equ 3           ; 2: first cluster; 0 for a root directory
OF_SIZE         equ 5           ; 4: bytes; 0 for a directory
OF_POS          equ 9           ; 4: the position — bytes in a file, an
                                ;    entry index in a directory
OF_CLUS         equ 13          ; 2: the cluster OF_POS is in; OF_CLUS_NONE
                                ;    = rebuild it from OF_FIRST, OF_CLUS_END
                                ;    = the chain ended before OF_POS
OF_DSEC         equ 15          ; 4: the sector holding the directory entry
OF_DIDX         equ 19          ;    and its index there (for the write side)
OF_ERRNO        equ 20          ; the errno owed to the next read (OFF_ERR)
OF_TAIL         equ 21          ; 2: the chain's last cluster, when the write
                                ;    side knows it; 0 = not known
                                ; 23 spare
OFF_DIR         equ 1           ; a directory
OFF_ROOT        equ 2           ; the root directory: a fixed area, no chain
OFF_MNT         equ 4           ; the synthetic /mnt
OFF_ERR         equ 8           ; a read or a write stopped short; OF_ERRNO
                                ; is owed to the next call
OFF_WR          equ 16          ; open for writing: the one writer
OFF_APPEND      equ 32          ; every write at the end (O_APPEND)
OFF_SHORT       equ 64          ; a directory: readdir's short form
OF_CLUS_NONE    equ 0
OF_CLUS_END     equ 0FFFFh

; A FAT directory entry, 32 bytes.
FE_NAME         equ 0           ; 11: name and extension, space padded
FE_ATTR         equ 11          ; DA_*
FE_NT           equ 12          ; the case bits: FN_*
FE_CTENTH       equ 13          ; creation time, tenths of a second: 0
FE_CTIME        equ 14          ; 2: creation time and
FE_CDATE        equ 16          ; 2: date
FE_ADATE        equ 18          ; 2: last-access date
FE_MTIME        equ 22          ; 2: time, then
FE_MDATE        equ 24          ; 2: date
FE_CLUS         equ 26          ; 2: first cluster
FE_SIZE         equ 28          ; 4
FE_SIZEOF       equ 32
FE_END          equ 00h         ; a first byte: no entry from here on
FN_LBASE        equ 08h         ; FE_NT: the name part is lower case
FN_LEXT         equ 10h         ;        the extension is
FE_LFN          equ 0Fh         ; an attribute: a long-name part
FE_FREE         equ 0E5h        ; a first byte: deleted

; ST_VFS: the filesystem's variables. The path and its cursor, the name
; being matched, the directory scan's cursor, the lookup's result (VR_*),
; the record being built, the read loop's scalars, and exec's (VX_*).
VV_PATH         equ ST_PATH     ; PATH_MAX: the path, copied in
; The long-name chain being read (ks_lfn.asm), what the scan hands on
; about it, and the case of the component being matched or made.
VL_N            equ ST_VFS+16   ; entries in the chain; 0 = none open
VL_NEXT         equ ST_VFS+17   ; the ordinal expected next
VL_SUM          equ ST_VFS+18   ; the checksum every part carries
VL_LEN          equ ST_VFS+19   ; the name's length
VL_DEAD         equ ST_VFS+20   ; 1: the chain is broken, skip to the entry
VL_LSEC         equ ST_VFS+21   ; 4: the sector of the chain's first part
VL_LIDX         equ ST_VFS+25   ;    and its index
VL_MODE         equ ST_VFS+26   ; 0: every chain read; 1: one of VL_WANT
VL_WANT         equ ST_VFS+27   ; a lookup: the component's length
VL_SHORT        equ ST_VFS+28   ; 1: VV_NAME holds the component as a short
                                ; name, to be compared too
VR_LN           equ ST_VFS+29   ; the found entry's chain: its entries, 0 none
VR_LSEC         equ ST_VFS+30   ; 4: the chain's first part, its sector
VR_LIDX         equ ST_VFS+34   ;    and index
VV_NT           equ ST_VFS+35   ; the component's case bits, FN_*
VV_CASE         equ ST_VFS+36   ; name83's scratch: bit 0 lower, 1 upper seen
VV_MIXED        equ ST_VFS+37   ; 1: a part of the component mixes its cases
; Making a name (ks_lfn.asm, ks_vfsw.asm): what the lookup gathers for the
; creation that follows it, and the parts being written.
VW_CREATE       equ ST_VFS+38   ; 1: the syscall makes the last component
VW_GATHER       equ ST_VFS+39   ; 1: this scan counts free slots and aliases
VW_EXCL         equ ST_VFS+40   ; 1: the entry at VW_OSEC/VW_OIDX on VW_OVOL
                                ; is no match (rename's own source)
VW_NLFN         equ ST_VFS+41   ; parts the new name needs; 0 for a short one
VW_RNEED        equ ST_VFS+42   ; slots wanted: VW_NLFN + 1
VW_RCNT         equ ST_VFS+43   ; free slots in the run being counted
VW_RFOUND       equ ST_VFS+44   ; 1: a run at VW_RSEC/VW_RIDX holds them, or
                                ; reaches the directory's end
VW_RSEC         equ ST_VFS+45   ; 4: the run's first slot: sector
VW_RIDX         equ ST_VFS+49   ;    and index
VW_ALIAS        equ ST_VFS+50   ; 11: the alias being built
VW_ATPOS        equ ST_VFS+61   ; where its ~ is
VW_AMAP         equ ST_VFS+62   ; 2: aliases ~1 to ~9 seen, bit n for ~n
VW_AEND         equ ST_VFS+64   ; 2: lfn_alias: past the component,
VW_ABASE        equ ST_VFS+66   ; 2: the base's start,
VW_AEXT         equ ST_VFS+68   ; 2: the last dot, 0 none
VW_PPOS         equ ST_VFS+70   ; lfn_part: the character being written
VW_PENT         equ ST_VFS+71   ; 32: a part being written; lfn_digit's
                                ; copy of VR_ENT across its scan
VW_OLN          equ ST_VFS+103  ; rename: the old entry's chain, its parts
VW_OLSEC        equ ST_VFS+104  ; 4: its first part's sector
VW_OLIDX        equ ST_VFS+108  ;    and index
VW_PN           equ ST_VFS+109  ; dir_new_name: the part to write next
VW_FN           equ ST_VFS+119  ; dir_free_name: parts left to mark
VW_ODCLUS       equ ST_VFS+120  ; 2: rename, rmdir: the entry's directory
VV_NAME         equ ST_VFS+128  ; 11: the component as a FAT name
VV_P            equ ST_VFS+139  ; 2: the cursor into VV_PATH
VV_VOL          equ ST_VFS+141  ; the node being walked: volume (VOL_NONE =
VV_CLUS         equ ST_VFS+142  ; 2: /mnt), cluster (0 = the volume's root)
VV_SSEC         equ ST_VFS+144  ; 4: the scan's sector
VV_SCLUS        equ ST_VFS+148  ; 2: its cluster
VV_SN           equ ST_VFS+150  ; sectors left in the cluster, or 2: in the
                                ;    root area
VV_SEGP         equ ST_VFS+152  ; 2: -> three segments, the pages a user
                                ;    address is read or written through
VR_KIND         equ ST_VFS+154  ; the result: VK_*
VR_VOL          equ ST_VFS+155
VR_CLUS         equ ST_VFS+156  ; 2
VR_ATTR         equ ST_VFS+158
VR_SIZE         equ ST_VFS+159  ; 4
VR_MTIME        equ ST_VFS+163  ; 4: time, date as the entry has them
VR_DSEC         equ ST_VFS+167  ; 4: the entry's sector
VR_DIDX         equ ST_VFS+171  ;    and index
VR_ENT          equ ST_VFS+172  ; 32: the entry itself
VV_RECX         equ ST_VFS+110  ; 9: the record from DE_ATTR on, being built
                                ; (its name is in ST_LNAME)
VV_RBUF         equ ST_VFS+228  ; 2: read: the user address
VV_RLEFT        equ ST_VFS+230  ; 2: bytes still to deliver
VV_RDONE        equ ST_VFS+232  ; 2: bytes delivered
VV_ROW          equ ST_VFS+234  ; 2: the open-file row
VV_T            equ ST_VFS+236  ; 8: scratch
VX_PAGES        equ ST_VFS+244  ; exec: pages the program wants
VX_FRESH        equ ST_VFS+245  ;    1 = new segments (a vfork child)
VX_SEG          equ ST_VFS+246  ; 3: the segments the image loads into
VX_BLEN         equ ST_VFS+249  ; 2: the argument block's length
VX_ARGC         equ ST_VFS+251
VX_SIZE         equ ST_VFS+252  ; 2: the file's size (a program is < 64K)
VX_LEFT         equ ST_VFS+254  ; 2: bytes still to load
VX_ADDR         equ ST_VFS+256  ; 2: where the next sector goes
VX_CLUS         equ ST_VFS+258  ; 2: the chain's cursor
VX_SIDX         equ ST_VFS+260  ;    sector index in the cluster
VX_OLDN         equ ST_VFS+261  ;    the process's pages before
VX_ARGV         equ ST_VFS+262  ; 2: the caller's vector
VX_BP           equ ST_VFS+264  ; 2: the block's fill pointer
VX_NEW          equ ST_VFS+266  ;    segments allocated by this exec
VX_SP           equ ST_VFS+267  ; 2: the new image's initial SP
VV_PN           equ ST_VFS+270  ; 2: the lookup's cursor past the component
VV_HASENT       equ ST_VFS+272  ; VR_ENT describes the node being walked
VV_U            equ ST_VFS+273  ; 2: um_copy: the user address,
VV_S            equ ST_VFS+275  ; 2: the storage offset,
VV_N            equ ST_VFS+277  ; 2: bytes left,
VV_DIR          equ ST_VFS+279  ;    0 in, 1 out
VV_B            equ ST_VFS+280  ; um_peek's byte
VV_RSEC         equ ST_VFS+281  ; 4: read: the sector OF_POS is in
VV_RSIDX        equ ST_VFS+285  ;    its index in the cluster
VV_RSPC         equ ST_VFS+286  ;    sectors per cluster
VX_SEC          equ ST_VFS+287  ; 4: exec: the sector being loaded
VX_SPAWN        equ ST_VFS+292  ; 0 exec: the image replaces the caller;
                                ; 1 spawnv: it is a new process's
VX_FDS          equ ST_VFS+293  ; 3: spawnv's descriptor map
VX_CPID         equ ST_VFS+296  ; spawnv: the child's pid
VX_OWNER        equ ST_VFS+297  ; whose segments ex_alloc takes: K_PID for
                                ; exec, the child's for spawnv
VX_ROW          equ ST_VFS+298  ; 2: spawnv: the child's row
VX_SIGDEF       equ ST_VFS+300  ; spawnv: SIGIGN_* bits the child drops
VV_SHORT        equ ST_VFS+301  ; 1: stat and getcwd write the short form
VV_SFVOL        equ ST_VFS+302  ; statfs: the volume,
VV_SFFLG        equ ST_VFS+303  ;    its B
VW_UTIME        equ ST_VFS+304  ; 2: utime: the time,
VW_UDATE        equ ST_VFS+306  ; 2: the date
VK_ENTRY        equ 0           ; VR_KIND: a directory entry (VR_ENT valid)
VK_ROOT         equ 1           ; the root directory of VR_VOL
VK_MNT          equ 2           ; the /mnt node
VK_NODE         equ 3           ; a directory known by its cluster alone
VK_PARENT       equ 4           ; left by a failed lookup (E_NOENT): the last
                                ; component is missing and VR_VOL/VR_CLUS
                                ; are its parent, VV_NAME its FAT name
VK_BADNAME      equ 5           ; the same, but the component is not a name
VK_NONE         equ 0FFh        ; a failed lookup that left nothing

; ST_VFSW: the write side's variables (ks_vfsw.asm, ks_fat.asm).
VW_PATH2        equ ST_PATH2    ; PATH_MAX: rename's second path
VW_ESEC         equ ST_VFSW+128 ; 4: dir_alloc_entry's slot: its sector
VW_EIDX         equ ST_VFSW+132 ;    and index
VW_TAIL         equ ST_VFSW+133 ; 2: a chain's last cluster
VW_NEWC         equ ST_VFSW+135 ; 2: a cluster just allocated
VW_DATE         equ ST_VFSW+137 ; 2: the stamp this syscall writes: date
VW_TIME         equ ST_VFSW+139 ; 2: and time
VW_FLAGS        equ ST_VFSW+141 ; open's flags
VW_ACC          equ ST_VFSW+142 ; its access mode, 0-2
VW_NATTR        equ ST_VFSW+143 ; dir_new_entry: the attribute
VW_NCLUS        equ ST_VFSW+144 ; 2: and the first cluster
VW_VAL          equ ST_VFSW+146 ; 2: fat_set: the value
VW_BUF0         equ ST_VFSW+148 ; 2: the entry's first byte's buffer
VW_P0           equ ST_VFSW+150 ; 2: -> its low byte
VW_P1           equ ST_VFSW+152 ; 2: -> its high byte
VW_AVOL         equ ST_VFSW+154 ; fat_alloc, fat_free_chain: the volume
VW_ACUR         equ ST_VFSW+155 ; 2: the cluster being probed
VW_ALEFT        equ ST_VFSW+157 ; 2: probes left in the circuit
VW_ALAST        equ ST_VFSW+159 ; 2: the volume's last cluster
VW_ZVOL         equ ST_VFSW+161 ; dir_zero_cluster: the volume
VW_ZSEC         equ ST_VFSW+162 ; 4: the sector being zeroed
VW_ZN           equ ST_VFSW+166 ;    sectors left
VW_BMODE        equ ST_VFSW+167 ; vfs_busy: 0 any row, 1 a writer's
VW_S32          equ ST_VFSW+168 ; 4: write: the size before
VW_P32          equ ST_VFSW+172 ; 4: where the caller's bytes go
VW_ERR          equ ST_VFSW+176 ;    the errno met, 0 = none
VW_OFF          equ ST_VFSW+177 ; 2: this sector: the offset in it,
VW_HOLE         equ ST_VFSW+179 ; 2: bytes of zeros to lay down,
VW_OFF2         equ ST_VFSW+181 ; 2: the offset after them,
VW_DATA         equ ST_VFSW+183 ; 2: the caller's bytes,
VW_BUF          equ ST_VFSW+185 ; 2: the buffer
VW_OSEC         equ ST_VFSW+187 ; 4: rename: the old entry's sector,
VW_OIDX         equ ST_VFSW+191 ;    index,
VW_OVOL         equ ST_VFSW+192 ;    volume,
VW_OATTR        equ ST_VFSW+193 ;    attribute,
VW_OCLUS        equ ST_VFSW+194 ; 2: first cluster;
VW_OENT         equ ST_VFSW+196 ; 32: the old entry itself
VW_DVOL         equ ST_VFSW+228 ;    the new name's directory: volume
VW_DCLUS        equ ST_VFSW+229 ; 2: and cluster
VW_NEW          equ ST_VFSW+231 ;    1 when the new name exists already
VW_TSEC         equ ST_VFSW+232 ; 4: that entry's sector,
VW_TIDX         equ ST_VFSW+236 ;    index,
VW_TCLUS        equ ST_VFSW+237 ; 2: first cluster
VW_ZB           equ ST_VFSW+239 ; 2: zw_write: the buffer of zeros, 0 = none
VW_ZBV          equ ST_VFSW+241 ;    the volume and
VW_ZBS          equ ST_VFSW+242 ; 4: sector its header names
VW_T            equ ST_VFSW+246 ; 8: scratch

; The legacy subsystem (dos.asm; src/leg/leg.asm is the layer). While a
; .COM program runs, page 3 shows a segment of its own — TPA to CFFFh, the
; layer from LEG_BASE, a copy of the kernel's page 3 from K_HINGE up — and
; the resident's page 3 comes back only to serve a syscall. The hinge is
; K_HINGE_LEN bytes at the same address in both images: two stubs that
; swap page 3 and point the page-0 interrupt vector at the handler the
; image in place has, and a small stack for the crossing. dosexec_finish
; writes both stubs at every launch.
K_HINGE         equ 0F100h      ; the hinge; the resident ends below it
K_HINGE_LEN     equ 64
K_HINGE2        equ K_HINGE+17  ; the second stub: the legacy page 3 back
K_HINGE_STUBS   equ 34          ; the two stubs' bytes
K_HINGE_SP      equ K_HINGE+K_HINGE_LEN ; the crossing's stack, downward
LEG_BASE        equ 0C400h      ; the layer: six CP/M version bytes,
LEG_BDOS        equ 0C406h      ;   the BDOS entry — the TPA's top —
LEG_VEC         equ 0C410h      ;   nine JPs: entry, a syscall's return,
                                ;   the interrupt trampoline, EXTBIO,
                                ;   RDSLT, WRSLT, CALSLT, ENASLT, CALLF
LEG_VARS        equ 0C430h      ;   what dos fills before dosenter:
LEG_SEGS        equ LEG_VARS+0  ;   3: the segments in pages 0-2 (the
                                ;      layer's PUT_Pn shadow from then on)
LEG_SEG3        equ LEG_VARS+3  ;   the legacy page-3 segment itself
LEG_DRIVE       equ LEG_VARS+4  ;   the current drive, 0 = A:
LEG_STARTED     equ LEG_VARS+5  ;   0 until the program has been entered
LEG_FD          equ LEG_VARS+6  ;   the .COM file, open for reading
LEG_SIZE        equ LEG_VARS+7  ;   2: its size
LEG_RAMPRI      equ LEG_VARS+9  ;   the RAM's slot, as pages 1 and 2 select
LEG_RAMSEC      equ LEG_VARS+10 ;   it: the primary in bits 5-4 and 3-2,
                                ;   the secondary the same, FFh when the
                                ;   slot is not expanded
LEG_PARAMS      equ 0C440h      ;   128: the tail as typed, 0-terminated
LEG_PROG        equ 0C4C0h      ;   16: the program's own file, for its
PR_DRIVE        equ 0           ;      PROGRAM string: its directory's
PR_CLUS         equ 1           ;      volume and cluster (2), then its
PR_ALIAS        equ 3           ;      8.3 alias, 0-terminated (13)
LEG_BIOS        equ 0C500h      ;   the CP/M BIOS jump table, 17 entries
LEG_MAX         equ K_HINGE-LEG_BASE ; the layer's largest length
LEG_TPA         equ LEG_BDOS-P0_PROG ; the largest .COM
LEG_EXIT        equ 0FFh        ; in C' at a crossing: k_dos_exit, A = code

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
B_CSRX          equ 0F3DDh      ; cursor column, 1-based
B_HOKVLD        equ 0FB20h      ; bit 0: EXTBIO is installed
B_RAMAD0        equ 0F341h      ; RAM slot of each page (RAMAD0-3)
B_GETPNT        equ 0F3FAh      ; the BIOS key buffer's read pointer
B_OLDKEY        equ 0FBDAh      ; 11: the keyboard matrix at the last scan
B_NEWKEY        equ 0FBE5h      ; 11: and at this one
B_CHSNS         equ 009Ch       ; BIOS: Z when no key waits
B_CHGET         equ 009Fh       ; BIOS: A = the next key, waiting for one
B_CHPUT         equ 00A2h       ; BIOS: A to the screen
B_BREAKX        equ 00B7h       ; BIOS: CF when CTRL+STOP is held
B_ENASLT        equ 0024h       ; BIOS: A = slot, HL = address
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
