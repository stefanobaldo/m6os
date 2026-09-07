# System calls

How a program talks to the m6 kernel. This is the whole interface a native
program has; everything below is fixed by `src/kernel/kernel.inc`, which is
the authoritative copy of every number here.

## The convention

A program calls the kernel through a jump table at a fixed address in page 3,
`K_SYS` = `C040h`, three bytes per entry: syscall *n* is `call C040h + 3n`.
There is no trap and no dispatch; the call lands on the kernel's routine, or
on a stub that switches the kernel's cold code in for the length of the call.
`kernel.inc` gives every syscall a name (`SYS_WRITE` …) and a macro, `sys n`.

- **Arguments** go in `A`, `HL`, `DE` and `BC`, as each syscall lists them.
- **The result** comes back in `HL`, and in `A` too when it fits a byte.
- **An error** is the carry flag set, with the error number in `A`
  (see *Errors*). On success the carry flag is clear.
- **Nothing else is preserved.** `BC`, `DE`, `IX`, `IY` and the alternate
  register set are undefined after a call; save what you need before it.

Interrupts stay enabled inside a syscall.

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
of up to 16 128 bytes.

## The table

| n | Name | In | Out | Errors |
|---|---|---|---|---|
| 0 | `exit` | `A` = status | does not return | — |
| 1 | `write` | `A` = fd, `HL` = buffer, `BC` = length | `HL` = bytes written | `EBADF`: fd is not 1 or 2 |
| 2 | `getpid` | — | `HL` = the process id | — |
| 3 | `sysconf` | `HL` = name | `HL` = value | `EINVAL`: not a name |
| 4–63 | — | — | — | `ENOSYS` |

`write` to file descriptor 1 or 2 goes to the console; a byte of value 10 is
a newline. There is no standard input yet. `sysconf` names: 0 `SC_PAGESIZE`
(16384), 1 `SC_SEGMENTS` (16K segments in the memory mapper the kernel runs
in), 2 `SC_SEGMENTS_USABLE` (the same, or the `mem=` cap), 3
`SC_SEGMENTS_FREE` (free right now).

## Errors

Error numbers are Seventh Edition Unix's, with `ENOSYS` from Linux. In
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
| 13 | `EACCES` | | |
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
