# Programs

What a program in a file looks like, and what it finds when the kernel
starts it with `exec`. `docs/syscalls.md` has the calls themselves; this
document is the contract between a file on a volume and the process it
becomes.

## The file

A program is a raw image of the memory it runs in, from `0100h` up, with
nothing before it — no header the loader strips, no relocation. Its first
six bytes are the kernel's:

| Offset | Bytes | What |
|---|---|---|
| `0000h` | `18 xx` | `jr start` — a jump over the header to the first instruction |
| `0002h` | `6D 36` | the signature, `"m6"` |
| `0004h` | 1 | pages the program wants, 1 to 3 |
| `0005h` | 1 | 0 |

`exec` refuses a file without the signature, with a page count that is not
1 to 3, or with anything but 0 in the last byte, with `ENOEXEC` — so an
MSX-DOS `.COM` program, which also begins at `0100h`, is never run by
accident. `tests/m6prog.inc` has a macro that writes the header.

An MSX-DOS 2 program — a `.COM` file, which also begins at `0100h` but
has no such header — is run by `dos`, with the MSX-DOS 2 layout built
around it for the run: [`dos.md`](dos.md).

Because the image is what the memory holds, the same file can be started
three ways: `spawnv` reads it from a volume into a new process, which is
how the system starts programs; `exec` reads it from a volume over the
calling process; `spawn` copies it from memory, in a program that has it
embedded or has read it in. `spawn` does not look at the header.

The pages byte says how much memory the program gets: one page is 16K from
`0000h`, three pages the whole 48K a process can have. A program that
fits in one page asks for one, so that more of them can run at once on a
128K machine — five 16K segments are free there once the kernel is up.

## What the program finds

The kernel loads the file at `0100h`, writes the 256 bytes below it (the
interrupt vector, its slot-switching routine, the exit stub `jp 0` lands
on) and builds, at the top of the program's highest page, the argument
block and the initial stack:

```
top of the highest page
    the argument block: the strings, then a table of pointers to them,
                        argc + 1 words, the last 0
    the kernel's 24-byte frame
SP  ->
```

On entry:

- `BC` = `argc`, the number of arguments;
- `HL` = `argv`, the address of the pointer table — `argv[0]` is what the
  caller put there: the shell puts the word typed, `cat` rather than
  `/bin/cat`, and a program's messages begin with it;
- `SP` is below the frame, with the exit stub's address on the stack, so a
  program that ends in `ret` exits with status 0;
- file descriptors 0, 1 and 2 are the caller's — the keyboard and the
  console unless the caller changed them — and so is the current
  directory; a program started by `spawnv` gets the three the caller's
  map named, and its 3 to 7 closed;
- the signals the caller ignores are ignored, but for those the caller
  asked `spawnv` to give it by default, until the program says otherwise
  with `signal` (`syscalls.md`, *Signals*);
- every other register is 0.

The terminal's mode — canonical or raw, see `syscalls.md` — is not the
program's: it is whatever the last program left, so a program that reads
lines sets canonical first, and a program that put the terminal in raw
mode is expected to put it back.

The argument block is at most 256 bytes, table included: a longer one is
refused with `E2BIG`. A program that reads no arguments need not look at
it. A program started with `spawn`, or with `spawnv` and no vector, finds
`BC` = 0 and an empty table.

## How much fits

`0100h` + the file + the argument block + the 24-byte frame must fit the
pages the header asks for, else `ENOEXEC`. With an empty argument vector a
one-page program's file can be at most 16 102 bytes.

## What spawnv costs

A one-sector program — a few hundred bytes — is running about 15 ms
after the call on an MSX2 at 3.58 MHz: the directory and table sectors
are usually in the kernel's cache, one data sector comes from the driver,
and the rest is the process's row, its memory and its arguments. In the
emulator, sixty `spawnv` and `waitpid` of such a program take 61 ticks, a
hint of about 17 ms each; the figure on the reference machine is the
gate's.

## What exec costs

A 16K program is loaded in 31 whole-sector transfers straight from the
storage driver into the program's page and one through the kernel's cache,
plus the directory and table sectors the lookup reads. Measured on an MSX2
at 3.58 MHz: about 200 ms through a driver that moves a sector in 4.8 ms
and about 220 ms through one that takes 5.4 ms, both to the nearest 60 Hz
tick, which is 17 ms. During it nothing else runs. `exec` from a `vfork`
child loads into fresh memory, so a one-page shell can start a three-page
program without a copy of itself in between.

## Writing a utility

The commands in `/bin` are built from `src/bin/<name>.asm` with the
library in `src/lib/`, one include per subject, so that a program pays
only for what it uses: `prog.inc` gives the header, the entry and the
exit; `out.inc` buffered output on descriptor 1; `in.inc` buffered input
by blocks and `line.inc` by bytes and lines; `err.inc` the messages in
the one form every command uses, `name: file: ENOENT`; `args.inc` the
arguments and options; `str.inc` the string routines; `path.inc` the
last component of a path, the join of a directory and a name, and
whether a path names a directory. `src/bin/cat.asm` is the smallest
complete example; the commands themselves are described in
[`commands.md`](commands.md).

A program's buffers live past the end of its file, declared with the
library's `bss` macro rather than `ds`: the assembler writes a `ds` into
the raw image, and a program of three hundred bytes with a 4K buffer
would otherwise load nine sectors instead of one. Each `bss` asserts that
the buffers end below `3EE8h`, the top of a one-page process less the
argument block and the kernel's frame, because the kernel checks the
file's fit and not the memory a program uses past it. Every command fits
one page; `make` refuses a `build/bin/*` above 16 102 bytes.
