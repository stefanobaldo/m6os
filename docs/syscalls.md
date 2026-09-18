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
with nothing typed, `wait` with no child exited, `sleep`, a pipe with
nothing to move, `vfork` until the child exits — gives the CPU to other
processes and returns when what it waited for has happened, or never
returns at all when a signal ends the process meanwhile (see *Signals*).

**A process may lose the CPU at any instruction and get it back later with
every register as it left it** — the kernel switches between processes on
the 60 Hz tick, round-robin, and saves the whole register set, alternate
set and index registers included, on the process's own stack. For that the
kernel may use up to 24 bytes of a process's stack at any instant: keep at
least that much room below `SP`. A syscall is not interrupted by a switch:
a tick that finds the process inside one marks the switch as owed, and the
process gives the CPU up when that call returns — so the wait another
process sees is at most one call long, a `write` of 4 KB to a file being
~50 ms on an MSX at 3.58 MHz, however long the caller goes on making
calls. A process that wants to give the CPU up sooner calls `yield`.

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
volume, opened with `open` and closed with `close` — or one end of a pipe
(see *Pipes*). A process starts with 0 the keyboard and 1 and 2 the
console, and a child made by `spawn`, `fork` or `vfork` inherits its
parent's eight, open files and pipe ends included: the two share the
file's position until one closes it. A child made by `spawnv` gets only
0, 1 and 2, chosen by the caller; its 3 to 7 start closed. `exec` keeps
them. `exit` closes them all. At most 24 files are open in the whole
system at once (`ENFILE`); a ninth descriptor in one process is
`EMFILE`.

A buffer a system call is to fill must lie below `C000h`, the kernel's
page: one that reaches it is refused with `EFAULT` and nothing is
written.

A path is a string of at most 255 bytes and a terminator: components
separated by `/`, each a name of up to 255 characters — any but
`" * / : < > ? \ |`, not ending in a dot or a space — matched without
regard to case against the entry's long name or its short alias; `.` is the directory
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

File descriptor 0 is the keyboard, and the kernel edits what is typed
before a program sees it. In **canonical mode**, the default, `read`
returns a line: every character typed is echoed to the screen as it
arrives, and the line is edited with a cursor that moves inside it:

| Key | Effect |
|---|---|
| a character, TAB | inserted at the cursor; a line already 127 bytes long drops it |
| BS | rubs out the character before the cursor |
| DEL | rubs out the character under the cursor |
| LEFT, RIGHT | the cursor one character back or on |
| HOME, ^A | the cursor to the start of the line |
| ^E | the cursor to its end |
| ^U | empties the line |
| ^L, SHIFT+HOME | clears the screen and writes again, at the top, what the line's first row held before the line began — a shell's prompt — and the line, the cursor where it was |
| RET | closes the line, wherever the cursor is, and becomes its last byte, LF (10) |
| UP, DOWN | dropped, unless the terminal is in recall mode (below) |
| INS, ESC, SELECT, the function keys | dropped without echo |

A `read` that asks for fewer bytes than the line holds gets that many,
and the rest waits for the next `read`, so a program reading a byte at a
time gets the line without waiting again. ^D at the start of a line makes
`read` return 0, once, as at the end of a file; ^D in the middle of one
closes it without an LF. A line holds 127 bytes; what is typed past that
is dropped. ^C and STOP are never bytes: they are the interrupt (see
*Signals*). The line being edited belongs to the terminal, not to the
process reading it.

`ttymode` (29) switches the keyboard to **raw mode** (1) and back to
canonical (0), for a pager or an editor that draws its own screen:
`read` then returns bytes as keys go down, one byte per key with the
modifiers in effect at that moment — nothing is echoed, nothing waits
for RET, and a key that means nothing on its own (SHIFT, F1) produces
nothing. The mode is the terminal's, not the process's: a program that
sets raw sets it for whoever reads next, so a program that reads lines
sets canonical first rather than trust what the last one left.

**Recall mode** (2) is canonical mode for a program that keeps a history
of lines, as the shell does: UP and DOWN, instead of being dropped, end
the `read` with two bytes — the arrow's own byte, 30 or 31, and an LF —
and leave the line being edited **open**: its bytes, its cursor and its
echo stay as they are, and the next `read` goes on editing it rather
than starting a new one. `ttyline` (32) replaces an open line with the
bytes at `HL`, `BC` of them (0 to 127): the old line's echo is erased,
the new one echoed with the cursor at its end; when no line is open it
opens one, so a program may also pre-type an answer before it reads.
The shell reads the arrow, looks the line up in its history, puts it in
place with `ttyline` and reads again; a program that ignores the two
bytes and reads again simply goes on with the line. A change of mode
drops an open line. In every mode, keys typed
before any process reads are kept — sixteen of them at most — and a key
held down repeats after half a second, twelve times a second. Letters
follow SHIFT and CAPS LOCK; CTRL with a letter gives 1 to 26; the keypad
gives its digits and operators. In raw mode the special keys give one
byte each:

| Key | Byte | Key | Byte | Key | Byte |
|---|---|---|---|---|---|
| BS | 8 | ESC | 27 | LEFT | 29 |
| TAB | 9 | RIGHT | 28 | UP | 30 |
| RET | 13 | HOME | 11 | DOWN | 31 |
| INS | 18 | SHIFT+HOME | 12 | DEL | 127 |
| SELECT | 24 | STOP | — the interrupt, never a byte | | |

A cursor is shown on the screen while a process is waiting in `read` and
hidden the rest of the time.

The console is read as well as written: `read` on a descriptor that is
the console — 1 and 2 as a process starts — takes from the keyboard
exactly as on 0, in whichever mode the terminal is in. A program whose
input is a file or a pipe reads what is typed there: `more` in
`ls -l | more` reads its keys on 2.

## The table

| n | Name | In | Out | Errors |
|---|---|---|---|---|
| 0 | `exit` | `A` = status | does not return | — |
| 1 | `write` | `A` = fd, `HL` = buffer, `BC` = length | `HL` = bytes written | `EBADF`: fd closed, the keyboard, or a file not open for writing; `EISDIR`; `ENOSPC`; `EIO`; `EROFS` |
| 2 | `getpid` | — | `HL` = the process id | — |
| 3 | `sysconf` | `HL` = name | `HL` = value | `EINVAL`: not a name |
| 4 | `spawn` | `HL` = image, `BC` = length, `A` = pages | `HL` = `A` = the child's pid | `EINVAL`: pages not 1–3, length 0, image in page 2, or too long for the pages; `EAGAIN`: 15 processes exist; `ENOMEM`: not enough free segments |
| 5 | `wait` | — | `H` = pid, `L` = `A` = status | `ECHILD`: no child alive or waiting to be reaped |
| 6 | `yield` | — | — | — |
| 7 | `read` | `A` = fd, `HL` = buffer, `BC` = length | `HL` = bytes read; 0 at the end of a file | `EBADF`: fd closed or a pipe's write end; `EINVAL`: length 0 on the keyboard or the console; `EFAULT`; `EISDIR`; `EIO` |
| 8 | `fork` | — | `HL` = `A` = the child's pid, 0 in the child | `EPERM`: called by process 0; `EAGAIN`: 15 processes exist; `ENOMEM`: not enough free segments |
| 9 | `vfork` | — | `HL` = `A` = the child's pid, 0 in the child | `EPERM`: called by process 0; `EAGAIN`: 15 processes exist |
| 10 | `open` | `HL` = path, `A` = flags (see *Files*) | `HL` = `A` = the descriptor | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EMFILE`, `ENFILE`, `EINVAL`: a flag that is not one, a name that cannot be made; `EISDIR`; `EACCES`; `EBUSY`; `ENOSPC`; `EIO`; `EROFS` |
| 11 | `close` | `A` = fd | — | `EBADF` |
| 12 | `lseek` | `A` = fd, `DE:HL` = offset, `B` = whence (0 start, 1 current, 2 end) | `DE:HL` = the position | `EBADF`; `EINVAL`: whence not 0–2, or a negative position |
| 13 | `stat` | `HL` = path, `DE` = a 24-byte buffer | — | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EIO` |
| 14 | `readdir` | `A` = fd (a directory), `HL` = a 24-byte buffer | `HL` = 1 (an entry), 0 (the end) | `EBADF`, `ENOTDIR`, `EIO` |
| 15 | `chdir` | `HL` = path (a directory) | — | `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EIO` |
| 16 | `exec` | `HL` = path, `DE` = argv (0: none) | does not return | `EPERM`: process 0; `ENOENT`, `ENOTDIR`, `EISDIR`, `ENOEXEC`, `E2BIG`, `ENOMEM`, `EIO` |
| 17 | `unlink` | `HL` = path (a file) | — | `ENOENT`, `ENOTDIR`, `EISDIR`, `EACCES`: read-only; `EBUSY`: open; `EIO`, `EROFS` |
| 18 | `mkdir` | `HL` = path | — | `ENOENT`: the parent; `ENOTDIR`, `EEXIST`, `EINVAL`: not a name; `ENOSPC`, `EIO`, `EROFS` |
| 19 | `rmdir` | `HL` = path (an empty directory) | — | `ENOENT`, `ENOTDIR`, `ENOTEMPTY`, `EBUSY`: open, somebody's current directory, a volume's root; `EINVAL`: `.` or `..`; `EIO`, `EROFS` |
| 20 | `rename` | `HL` = old path, `DE` = new path | — | `ENOENT`, `ENOTDIR`, `EXDEV`: another volume; `EEXIST`: a directory on either side exists; `EINVAL`: not a name, or a directory into itself; `EACCES`, `EBUSY`, `ENOSPC`, `EIO`, `EROFS` |
| 21 | `pipe` | — | `L` = the read end, `H` = the write end | `EMFILE`: fewer than two descriptors free; `ENFILE`: four pipes exist |
| 22 | `spawnv` | `HL` = path, `DE` = argv (0: none), `BC` = a 3-byte map, `A` = signals the child takes by default (see *Processes from files*) | `HL` = `A` = the child's pid | `ENOENT`, `ENOTDIR`, `EISDIR`, `ENAMETOOLONG`, `ENOEXEC`, `E2BIG`, `EBADF`: a map entry is not `FFh` or an open descriptor; `EAGAIN`: 15 processes exist; `ENOMEM`; `EIO` |
| 23 | `waitpid` | `A` = pid (0: any child), `B` = flags (1: `WNOHANG`) | `H` = pid, `L` = `A` = status; `HL` = 0 with `WNOHANG` and nothing exited | `ECHILD`: no child, or not the caller's |
| 24 | `sleep` | `HL` = ticks | `HL` = 0 | — |
| 25 | `procinfo` | `A` = pid, `HL` = a 24-byte buffer | — | `EINVAL`: pid not 0–15; `ESRCH`: no such process; `EFAULT` |
| 26 | `getcwd` | `HL` = buffer, `BC` = its size | `HL` = the length | `ENAMETOOLONG`: the path or the buffer too short; `EFAULT`; `EIO` |
| 27 | `time` | — | `HL` = FAT date, `DE` = FAT time | — |
| 28 | `chmod` | `HL` = path, `A` = attributes | — | `EINVAL`: a bit that is not one; `ENOENT`, `ENOTDIR`, `ENAMETOOLONG`, `EACCES`: a volume's root or `/mnt`; `EROFS`, `EIO` |
| 29 | `ttymode` | `A` = 0 canonical, 1 raw, 2 recall | `L` = the mode that was | `EINVAL`: not 0, 1 or 2 |
| 30 | `kill` | `A` = pid, `B` = signal | — | `EPERM`: pid 0; `EINVAL`: pid past 15, or a signal that is none of the four; `ESRCH`: no such process |
| 31 | `signal` | `A` = signal, `B` = 0 (the default) or 1 (ignore) | `L` = the action that was | `EINVAL`: `SIGKILL`, or not a signal |
| 32 | `ttyline` | `HL` = bytes, `BC` = how many, 0 to 127 | — | `EINVAL`: more than 127; `EFAULT`: a buffer reaching page 3 |
| 33 | `dosenter` | `A` = a segment of the caller's, filled as the legacy layer expects; pages 1 and 2 mapped with `segmap` (see *MSX-DOS programs*) | does not return | `EPERM`: process 0; `EBUSY`: an MSX-DOS program runs already; `EINVAL`: not the caller's segment |
| 34 | `segalloc` | — | `HL` = `A` = a segment, the caller's | `ENOMEM`; `EPERM`: process 0 |
| 35 | `segfree` | `A` = a segment of the caller's, not one of its pages | `HL` = 0 | `EINVAL` |
| 36 | `segmap` | `A` = a page, 1 or 2; `B` = a segment of the caller's | `HL` = 0 | `EINVAL`: the page, or not the caller's segment |
| 37–47 | — | — | — | `ENOSYS` |

`write` to a descriptor that is the console goes to the screen and `read`
from one that is the keyboard or the console takes from the keyboard, as
*The console* says: that
`read` blocks until at least one byte is there and returns what is there,
up to `BC`. `read` from an open file returns the next bytes of the file,
up to `BC`, advances the position by as many, and returns 0 at the end;
a whole sector read into a buffer on a 256-byte boundary goes from the
storage driver straight into the program's memory, and everything else
through the kernel's cache and a copy. `write` to a file open for writing
puts the bytes at the position and advances it; writing past the end
extends the file, and a position left past the end by `lseek` fills the
gap with zeros. Every byte a `write` returns is on the disk when it
returns — the data first, then the allocation table in both its copies,
then the directory entry — so there is nothing to flush and a card pulled
after the call has what the call wrote. A whole sector from a buffer on a
256-byte boundary goes straight to the driver; anything else is read,
changed and written back, about 10 ms more per sector on an MSX at 3.58
MHz, so a program writes in the largest pieces it can. A `write` that ran
out of space or hit an error after writing some bytes returns how many;
the error comes back from the next call.
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
has — and reaps it: `H` is its pid, `L` its exit status. `waitpid` does
the same for one child named by its pid, or for any child when `A` is 0;
with `WNOHANG` in `B` it does not block: `HL` is 0 when children live and
none has exited. A pid that is not the caller's child is `ECHILD`.
`yield` hands the CPU to the next runnable process and returns when the
caller's turn comes round again; with no other process runnable it
returns at once. `sleep` gives the CPU up for `HL` ticks of the 60 Hz
clock — 60 is a second — and returns when they have passed; 0 is a
`yield`. `procinfo` copies a process's row of the kernel's tables, 24
bytes as the kernel keeps them: the layout is the kernel's own and moves
with it, so only a program shipped with the kernel should read it.

## Processes from files

`spawnv` creates a process from a program in a file — the file
[`programs.md`](programs.md) describes — in one call: it makes the
process, loads the file into fresh memory, hands it `argv` as `exec`
does, and returns the child's pid to the caller, which keeps the CPU as
after `spawn`. `BC` points at three bytes that say what the child's
descriptors 0, 1 and 2 are: each is one of the caller's descriptors, or
`FFh` for the caller's own of the same number. The child gets those three
and nothing else — its 3 to 7 start closed — so a pipe end the caller
still holds does not leak into a child that must not have it. A
descriptor named in the map that is closed is `EBADF`, and every refusal
leaves the caller as it was: the file is loaded into the child's memory,
never the caller's. `A` names signals the child takes by default even
though the caller ignores them, as the bits `SIGIGN_INT` (1), `SIGIGN_PIPE`
(2) and `SIGIGN_TERM` (4); every other signal the caller ignores, the child
ignores too, and `A` = 0 gives the child exactly the caller's. This is how
the system starts programs; `vfork` and `exec` remain for programs written
around them.

## Pipes

`pipe` makes a pipe and returns its two ends as descriptors, the read end
in `L`, the write end in `H` — the two lowest free. Bytes written to the
write end are read from the read end in the same order. A pipe holds 256
bytes: `write` delivers every byte it is given, blocking while the pipe
is full and a reader has yet to take some; `read` returns what is there,
1 to 256 bytes and at most `BC`, blocking while the pipe is empty and a
writer still holds the write end. When every write end is closed, `read`
returns 0 at the end of what was written. A `write` to a pipe whose every
read end is closed ends the writing process with status 141, before a
byte moves, as `SIGPIPE` does under Unix — so `yes | head` ends by itself;
a process that has chosen to ignore `SIGPIPE` (see *Signals*) gets `EPIPE`
from the `write` instead and goes on. Four pipes exist at once (`ENFILE`). A pipe end is closed with `close`,
inherited like a file by `spawn`, `fork` and `vfork`, handed to a child by
`spawnv`'s map, and closed by `exit`: a pipe is gone when nobody holds
either end. Process 0, the kernel's own thread, may make pipes and hand
them to children but not read or write them (`EPERM`).

On an MSX at 3.58 MHz, 256 bytes through a pipe cost the two copies —
about 1.65 ms each — and the two changes of process; a producer that
writes in pieces of 256, 512 or 1024 bytes pays nothing for the pipe's
boundaries.

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

## Signals

Four signals, each of which ends the process it reaches unless that
process has chosen to ignore it; no signal runs a handler. **`SIGINT`**
(2) is what ^C or STOP on the keyboard sends — to every process that does
not ignore it, there being no process groups: a shell ignores it and
starts a foreground command with `spawnv`'s `A` = `SIGIGN_INT`, so the
command takes the default and dies while the shell reads on, and a job
meant to survive ^C is started with `A` = 0 and inherits the ignore. The
shell never lowers its own guard to start a command: a ^C that lands while
it does would end the shell. A ^C that lands while `spawnv` is still
loading a command reaches nobody, the command not being a process yet, so
the command runs; a second ^C ends it. **`SIGPIPE`** (13) is what a
`write` to a pipe with no reader delivers to the writer (see *Pipes*). **`SIGTERM`** (15)
is `kill`'s ordinary request to end. **`SIGKILL`** (9) cannot be ignored.
A process a signal ended reports 128 plus the signal to `wait` and
`waitpid`: 130 after ^C, 137, 141, 143.

`kill` sends the signal in `B` to the process whose pid is in `A`; a
process may end itself this way, and does so at once. `kill` of a zombie,
or of a process that ignores the signal, succeeds and does nothing.
`signal` makes the caller take the signal in `A` by default (`B` = 0) or
ignore it (`B` = 1) and returns what it did before; a child inherits its
parent's choices, and `exec` keeps them.

A signal never interrupts a system call. A process blocked in `read`,
`wait`, `waitpid`, `sleep` or on a pipe ends at once; one inside a call
that is running — a `read` or `write` of a file, an `exec` — ends when
that call returns, a one-page program without fail, a two- or three-page
one at the next tick that finds it between calls. A `write` of 64 KB to a
file therefore ends the process at its end, several hundred milliseconds
after the ^C on an MSX at 3.58 MHz. The process's open files and pipe
ends are closed as at any `exit`. A ^C also discards what was typed ahead
and the line being edited; and when it ended nobody — every process
ignores it, or only a shell at its prompt is running — the byte 3 is
queued in their place, which a canonical `read` delivers as an empty
line and a raw one as itself, so that a shell prints a fresh prompt and
an editor that ignores `SIGINT` sees the key.

## Segments, and MSX-DOS programs

A process owns pages 0–2; `segalloc` gives it a 16K segment beyond them,
owned by it and returned with everything else when it exits, and
`segfree` returns one early — never one of its own pages. `segmap` puts
one of its segments into page 1 or 2 and keeps it there: the kernel
records it as the process's page, so a system call that copies to or
from a buffer in that page reaches the segment, and the page comes back
mapped after every call and every switch. A segment mapped by writing
the mapper register directly, without `segmap`, is lost at the first
system call, whose return puts the recorded page back.

`dosenter` is how a process becomes an MSX-DOS 2 program: the caller has
built, in a segment of its own, the layer such a program finds above its
TPA — [`dos.md`](dos.md) says what, and `/bin/dos` is the program that
does it — and has its pages 1 and 2 mapped to the program's through
`segmap`. The call swaps that segment into page 3 in place of the kernel's
own, enters the layer, and never returns; the layer loads the program
through `read` and runs it, and the process exits with the program's
termination code as its status. One such program runs at a time.

## Files

`open` names a file or a directory and returns the lowest closed
descriptor. Bits 0–1 of the flags are the access mode: 0 `O_RDONLY`, 1
`O_WRONLY`, 2 `O_RDWR`; `O_CREAT` (`40h`) makes the file when it is not
there, with the archive bit and the time from the clock; `O_TRUNC`
(`80h`), with a writable mode, empties an existing file first;
`O_APPEND` (`08h`) puts every write at the end. A file has one writer at
a time: opening for writing fails with `EBUSY` while anyone has the file
open, and opening for reading fails while a writer has it. A file whose
read-only attribute is set cannot be opened for writing, renamed or
removed (`EACCES`); nothing here clears that attribute. A directory can
be opened read-only, for `readdir`. `close` closes one descriptor. `lseek` moves an open file's position: `whence` 0 sets it to
the offset, 1 adds the offset to the position, 2 to the file's size; the
offset is a signed 32-bit number in `DE:HL`, and the new position comes
back the same way. A position past the end is allowed and a `read` there
returns 0; a negative one is `EINVAL`.

`stat` and `readdir` fill the same 265-byte record:

| Offset | Size | What |
|---|---|---|
| 0 | 256 | the name, 0-terminated — the long name when the entry has one, else the short name as stored, lower-cased where its case bits say so; `.` and `..` as they are; what follows the terminator is left as it was |
| 256 | 1 | the FAT attributes: `01h` read-only, `02h` hidden, `04h` system, `10h` directory, `20h` archive |
| 257 | 4 | the size in bytes; 0 for a directory |
| 261 | 4 | the modification time: the FAT date word, then the time word |

`stat` describes what a path names; a volume's root is named by its
letter, `/mnt` by `mnt`. `readdir` on a descriptor opened on a directory
returns its entries one per call, in the order they are stored, skipping
deleted ones, volume labels and long-name entries, and 0 at the end;
`lseek` to 0 rewinds it. `/mnt` lists a directory per mounted volume,
`a` to `h`. `chdir` makes a directory the process's current one.

`unlink` removes a file — its entry first, then its clusters; a file that
is open cannot be removed. `mkdir` makes an empty directory where the
last component of the path is missing, with `.` and `..`. `rmdir`
removes a directory holding nothing but those two; not a volume's root,
not a directory that is open or is some process's current directory.
`rename` gives an entry a new name, in the same directory or another one
of the same volume; a file may take an existing file's name, whose
contents are then gone; a directory keeps its contents and its `..` is
made to name the new parent. Names are FAT short names, and a name that
is not one is `EINVAL` when it has to be made. Long-name entries a PC
wrote beside a renamed or removed file are left where they are.

The modification time of a file is set when it is created, and on every
`write`, from the machine's clock; the directory holding it is not
touched. `time` returns that clock's reading as the same two FAT words,
the date in `HL` and the time in `DE`. `chmod` sets a file's or a
directory's attributes to the bits in `A` — `01h` read-only, `02h`
hidden, `04h` system, `20h` archive, in any combination; `10h`, the
directory bit, stays as it is and any other bit is `EINVAL` — and is the
one way to clear a read-only bit from m6; a volume's root and `/mnt`
have no entry to change (`EACCES`). `getcwd` writes the process's
current directory as a path into the buffer, 0-terminated, and returns
its length: `/` for the boot volume's root, `/mnt/b/dir` for a directory
on another volume, `/mnt` for the directory of volumes — the shortest
name that reaches it, whatever `chdir` was given; a buffer too small for
the path and its terminator is `ENAMETOOLONG`. `exec`
replaces the calling process's image with the program in the file, as
[`programs.md`](programs.md) describes, and returns only when it could
not: the caller's image is intact then, whatever the error. A process
whose parent is waiting in `vfork` gets fresh memory for the new image,
and the parent wakes as the image starts.

## Errors

Error numbers are Seventh Edition Unix's, with `ENOSYS`, `ENOTEMPTY` and
`ENAMETOOLONG` from Linux. In
`kernel.inc` each is `E_` plus the name without its `E`: `E_BADF`, `E_INVAL`.

| Number | Name | Number | Name |
|---|---|---|---|
| 1 | `EPERM` | | |
| 2 | `ENOENT` | | |
| 3 | `ESRCH` | | |
| 4 | `EINTR` | 18 | `EXDEV` |
| 5 | `EIO` | 19 | `ENODEV` |
| 6 | `ENXIO` | 20 | `ENOTDIR` |
| 7 | `E2BIG` | 21 | `EISDIR` |
| 8 | `ENOEXEC` | 22 | `EINVAL` |
| 9 | `EBADF` | 23 | `ENFILE` |
| 10 | `ECHILD` | 24 | `EMFILE` |
| 11 | `EAGAIN` | 28 | `ENOSPC` |
| 12 | `ENOMEM` | 30 | `EROFS` |
| 13 | `EACCES` | 32 | `EPIPE` |
| 14 | `EFAULT` | 38 | `ENOSYS` |
| 16 | `EBUSY` | 39 | `ENOTEMPTY` |
| 17 | `EEXIST` | 63 | `ENAMETOOLONG` |

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
