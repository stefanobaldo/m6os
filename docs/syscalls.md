# System calls

How a program talks to the m6 kernel. This is the whole interface a native
program has; everything below is fixed by `src/kernel/kernel.inc`, which is
the authoritative copy of every number here.

## The convention

A program calls the kernel through a jump table at a fixed address in page 3,
`K_SYS` = `C070h`, three bytes per entry: syscall *n* is `call C070h + 3n`.
There is no trap and no dispatch; the call lands on the kernel's routine, or
on a stub that switches the kernel's cold code in for the length of the call.
`kernel.inc` gives every syscall a name (`SYS_WRITE` …) and a macro, `sys n`.

- **Arguments** go in `A`, `HL`, `DE` and `BC`, as each syscall lists them.
- **The result** comes back in `HL`, and in `A` too when it fits a byte.
  One exception: `lseek` returns a 32-bit position in `DE:HL`, `DE` high.
- **An error** is the carry flag set, with the error number in `A`
  (see *Errors*). On success the carry flag is clear.
- **Nothing else is preserved.** `BC`, `DE`, `IX`, `IY` and the alternate
  register set are undefined after a call; save what you need before it.

Interrupts stay enabled inside a syscall. A syscall that blocks — `read`
with nothing typed, `wait` with no child exited, `vfork` until the child
exits — gives the CPU to other processes and returns when what it waited
for has happened.

**A process may lose the CPU at any instruction and get it back later with
every register as it left it** — the kernel switches between processes on
the 60 Hz tick, round-robin, and saves the whole register set, alternate
set and index registers included, on the process's own stack. For that the
kernel may use up to 24 bytes of a process's stack at any instant: keep at
least that much room below `SP`. A syscall is not interrupted by a switch;
a process that wants to give the CPU up before its turn ends calls `yield`.

## What a process sees

A process owns pages 0–2 — `0000h`–`BFFFh`, 48K of contiguous memory — and
sees nothing of page 3 but the table it calls. The kernel writes the first
256 bytes of page 0; the program starts at `0100h`, as an MSX-DOS `.COM`
program does, and the rest of every page is its own.

| Address | What is there |
|---|---|
| `0000h` | `jp 0060h` — `jp 0` ends the process with status 0 |
| `0038h` | the interrupt vector |
| `0040h`–`0050h` | the kernel's secondary-slot switching routine |
| `0060h` | `xor a` · `jp exit` — where a program's final `ret` lands |
| `0100h` | the program |

On entry `SP` is two below the top of the process's highest page — `3FFEh`
for a one-page process, `BFFEh` for three pages — with the address `0060h`
on the stack, so a program that runs off its end with `ret` exits with
status 0. The size of a program decides its pages: one page holds a program
of up to 16 104 bytes (the last 24 are the kernel's, see above).

A process is created by `spawn` from a program image in the memory of the
process that creates it, or by `fork` or `vfork` as a second copy of the
one that calls it — and `exec` replaces a process's image with a program
read from a file (see [`programs.md`](programs.md)). A process has a
process id from 1 to 15 — its parent learns
it from `spawn`, `fork` or `vfork` and gets it back from `wait`. The kernel runs at
most 15 processes at once (`sysconf` says so); a process id is reused
once its process has exited and its parent has waited for it. A process
that has exited but not been waited for is a zombie: its memory is free,
its id and status are held until the parent's `wait`. When a parent exits
first, its living children are on their own — nobody will wait for them,
and they disappear entirely when they exit.

## File descriptors

A process has eight file descriptors, 0 to 7. Each is closed, or the
console, or the keyboard, or an open file — a file or directory on a
volume, opened with `open` and closed with `close`. A process starts with
0 the keyboard and 1 and 2 the console, and a child made by `spawn`,
`fork` or `vfork` inherits its parent's eight, open files included: the
two share the file's position until one closes it. `exec` keeps them.
`exit` closes them all. At most 24 files are open in the whole system at
once (`ENFILE`); a ninth descriptor in one process is `EMFILE`.

A path is a string of at most 127 bytes and a terminator: components
separated by `/`, each a FAT name of up to eight characters, a dot and up
to three more, matched without regard to case; `.` is the directory
itself and `..` its parent. A path that begins with `/` starts at the
root of the boot volume; any other starts at the process's current
directory, which `chdir` sets and a child inherits. `/mnt` is the
directory of every mounted volume, `/mnt/a` to `/mnt/h`, as
[`storage.md`](storage.md) describes.

## The console

File descriptors 1 and 2 are the screen: 80 columns by 24 rows of text,
which the kernel programs itself. A byte of 20h or above is a character
at the cursor, which moves right and wraps to the next row at column 80;
a row past the bottom scrolls the screen up. Five control bytes are
understood: BS (8) moves the cursor back one column, TAB (9) to the next
multiple of 8, LF (10) to the start of the next row, FF (12) clears the
screen and puts the cursor at the top, CR (13) to the start of the row.
Every other byte below 20h does nothing. There are no escape sequences.
A write of many lines scrolls once, by all of them, not once per line.

File descriptor 0 is the keyboard. `read` returns bytes as keys go down,
one byte per key with the modifiers in effect at that moment — nothing is
echoed, nothing waits for RET, and a key that means nothing on its own
(SHIFT, F1) produces nothing. Keys typed before any process reads are kept
— sixteen of them at most — and a key held down repeats after half a
second, twelve times a second. Letters follow SHIFT and CAPS LOCK; CTRL
with a letter gives 1 to 26; the keypad gives its digits and operators.
The special keys give one byte each:

| Key | Byte | Key | Byte | Key | Byte |
|---|---|---|---|---|---|
| BS | 8 | ESC | 27 | LEFT | 29 |
| TAB | 9 | RIGHT | 28 | UP | 30 |
| RET | 13 | HOME | 11 | DOWN | 31 |
| INS | 18 | SHIFT+HOME | 12 | DEL | 127 |
| SELECT | 24 | STOP | 3 | | |

A cursor is shown on the screen while a process is waiting in `read` and
hidden the rest of the time.

## The table

| n | Name | In | Out | Errors |
|---|---|---|---|---|
| 0 | `exit` | `A` = status | does not return | — |
| 1 | `write` | `A` = fd, `HL` = buffer, `BC` = length | `HL` = bytes written | `EBADF`: fd is not the console |
| 2 | `getpid` | — | `HL` = the process id | — |
| 3 | `sysconf` | `HL` = name | `HL` = value | `EINVAL`: not a name |
| 4 | `spawn` | `HL` = image, `BC` = length, `A` = pages | `HL` = `A` = the child's pid | `EINVAL`: pages not 1–3, length 0, image in page 2, or too long for the pages; `EAGAIN`: 15 processes exist; `ENOMEM`: not enough free segments |
| 5 | `wait` | — | `H` = pid, `L` = `A` = status | `ECHILD`: no child alive or waiting to be reaped |
| 6 | `yield` | — | — | — |
| 7 | `read` | `A` = fd, `HL` = buffer, `BC` = length | `HL` = bytes read; 0 at the end of a file | `EBADF`: fd closed or the console; `EINVAL`: length 0 on the keyboard; `EISDIR`; `EIO` |
| 8 | `fork` | — | `HL` = `A` = the child's pid, 0 in the child | `EPERM`: called by process 0; `EAGAIN`: 15 processes exist; `ENOMEM`: not enough free segments |
| 9 | `vfork` | — | `HL` = `A` = the child's pid, 0 in the child | `EPERM`: called by process 0; `EAGAIN`: 15 processes exist |
| 10 | `open` | `HL` = path, `A` = flags (0: read only) | `HL` = `A` = the descriptor | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EMFILE`, `ENFILE`, `EINVAL`: flags not 0, `EIO` |
| 11 | `close` | `A` = fd | — | `EBADF` |
| 12 | `lseek` | `A` = fd, `DE:HL` = offset, `B` = whence (0 start, 1 current, 2 end) | `DE:HL` = the position | `EBADF`; `EINVAL`: whence not 0–2, or a negative position |
| 13 | `stat` | `HL` = path, `DE` = a 24-byte buffer | — | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EIO` |
| 14 | `readdir` | `A` = fd (a directory), `HL` = a 24-byte buffer | `HL` = 1 (an entry), 0 (the end) | `EBADF`, `ENOTDIR`, `EIO` |
| 15 | `chdir` | `HL` = path (a directory) | — | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EIO` |
| 16 | `exec` | `HL` = path, `DE` = argv (0: none) | does not return | `EPERM`: process 0; `ENOENT`, `ENOTDIR`, `EISDIR`, `ENOEXEC`, `E2BIG`, `ENOMEM`, `EIO` |
| 17–47 | — | — | — | `ENOSYS` |

`write` to a descriptor that is the console goes to the screen and `read`
from one that is the keyboard takes from it, as *The console* says: that
`read` blocks until at least one byte is there and returns what is there,
up to `BC`. `read` from an open file returns the next bytes of the file,
up to `BC`, advances the position by as many, and returns 0 at the end;
a whole sector read into a buffer on a 256-byte boundary goes from the
storage driver straight into the program's memory, and everything else
through the kernel's cache and a copy. `write` to a file is `EBADF` in
this version: files are read only.
`sysconf` names: 0 `SC_PAGESIZE`
(16384), 1 `SC_SEGMENTS` (16K segments in the memory mapper the kernel runs
in), 2 `SC_SEGMENTS_USABLE` (the same, or the `mem=` cap), 3
`SC_SEGMENTS_FREE` (free right now), 4 `SC_CHILD_MAX` (processes the kernel
runs at once, 15).

`spawn` copies the image, `BC` bytes at `HL` in the caller's pages 0–1, to
`0100h` of a new process of `A` pages, and makes it runnable; the caller
keeps the CPU until the next tick or its own `yield` or `wait`. The child
starts as *What a process sees* says. `wait` blocks until one of the
caller's children exits — or returns at once with a child that already
has — and reaps it: `H` is its pid, `L` its exit status. `yield` hands the
CPU to the next runnable process and returns when the caller's turn comes
round again; with no other process runnable it returns at once.

`fork` makes a second process that is a copy of the caller — every page,
the stack included — and returns twice: in the caller with the child's
pid, in the child with 0. The copy costs about 105 ms per 16K page on an
MSX at 3.58 MHz, and during it nothing else runs; `spawn` is how the
system creates processes, `fork` is there for programs written around it.
`vfork` makes a child that shares the caller's memory and stack instead
of copying them, and suspends the caller until the child exits (later:
or replaces itself with `exec`), so it costs no copy. The child of a
`vfork` may do nothing but call `exit` — in particular it must not return
from the function that called `vfork`, or write above the stack pointer
it was born with, because the parent resumes on that same stack. Both
children are waited for with `wait` like any other. Process 0, the
kernel's own thread, has no memory of its own to copy or share and gets
`EPERM` from both.

## Files

`open` names a file or a directory and returns the lowest closed
descriptor; the flags must be 0 (`O_RDONLY`) in this version. `close`
closes one. `lseek` moves an open file's position: `whence` 0 sets it to
the offset, 1 adds the offset to the position, 2 to the file's size; the
offset is a signed 32-bit number in `DE:HL`, and the new position comes
back the same way. A position past the end is allowed and a `read` there
returns 0; a negative one is `EINVAL`.

`stat` and `readdir` fill the same 24-byte record:

| Offset | Size | What |
|---|---|---|
| 0 | 13 | the name, `name.ext` in lower case, 0-terminated — `.` and `..` as they are |
| 13 | 1 | the FAT attributes: `01h` read-only, `02h` hidden, `04h` system, `10h` directory, `20h` archive |
| 14 | 4 | the size in bytes; 0 for a directory |
| 18 | 4 | the modification time: the FAT date word, then the time word |
| 22 | 2 | 0 |

`stat` describes what a path names; a volume's root is named by its
letter, `/mnt` by `mnt`. `readdir` on a descriptor opened on a directory
returns its entries one per call, in the order they are stored, skipping
deleted ones, volume labels and long-name entries, and 0 at the end;
`lseek` to 0 rewinds it. `/mnt` lists a directory per mounted volume,
`a` to `h`. `chdir` makes a directory the process's current one. `exec`
replaces the calling process's image with the program in the file, as
[`programs.md`](programs.md) describes, and returns only when it could
not: the caller's image is intact then, whatever the error. A process
whose parent is waiting in `vfork` gets fresh memory for the new image,
and the parent wakes as the image starts.

## Errors

Error numbers are Seventh Edition Unix's, with `ENOSYS` and `ENAMETOOLONG`
from Linux. In
`kernel.inc` each is `E_` plus the name without its `E`: `E_BADF`, `E_INVAL`.

| Number | Name | Number | Name |
|---|---|---|---|
| 1 | `EPERM` | 16 | `EBUSY` |
| 2 | `ENOENT` | 17 | `EEXIST` |
| 3 | `ESRCH` | 19 | `ENODEV` |
| 4 | `EINTR` | 20 | `ENOTDIR` |
| 5 | `EIO` | 21 | `EISDIR` |
| 6 | `ENXIO` | 22 | `EINVAL` |
| 7 | `E2BIG` | 23 | `ENFILE` |
| 8 | `ENOEXEC` | 24 | `EMFILE` |
| 9 | `EBADF` | 28 | `ENOSPC` |
| 10 | `ECHILD` | 30 | `EROFS` |
| 11 | `EAGAIN` | 32 | `EPIPE` |
| 12 | `ENOMEM` | 38 | `ENOSYS` |
| 13 | `EACCES` | 63 | `ENAMETOOLONG` |
| 14 | `EFAULT` | | |

## An example

```
        include "kernel/kernel.inc"
        org     0100h
        ld      a,1                     ; stdout
        ld      hl,msg
        ld      bc,msg_len
        sys     SYS_WRITE
        ld      a,0
        sys     SYS_EXIT
msg:    db      "hello",10
msg_len equ     $-msg
```
