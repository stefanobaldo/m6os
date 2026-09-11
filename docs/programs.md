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

Because the image is what the memory holds, the same file can be started
two ways: `exec` reads it from a volume; `spawn` copies it from memory, in
a program that has it embedded or has read it in. `spawn` does not look at
the header.

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
  caller put there, by convention the path it named the program with;
- `SP` is below the frame, with the exit stub's address on the stack, so a
  program that ends in `ret` exits with status 0;
- file descriptors 0, 1 and 2 are the caller's — the keyboard and the
  console unless the caller changed them — and so is the current
  directory;
- every other register is 0.

The argument block is at most 256 bytes, table included: a longer one is
refused with `E2BIG`. A program that reads no arguments need not look at
it. A program started with `spawn` finds `BC` = 0 and an empty table.

## How much fits

`0100h` + the file + the argument block + the 24-byte frame must fit the
pages the header asks for, else `ENOEXEC`. With an empty argument vector a
one-page program's file can be at most 16 102 bytes.

## What exec costs

A 16K program is loaded in 31 whole-sector transfers straight from the
storage driver into the program's page and one through the kernel's cache,
plus the directory and table sectors the lookup reads — about 200 ms on an
MSX at 3.58 MHz through a driver that moves a sector in 5.4 ms. During it
nothing else runs. `exec` from a `vfork` child loads into fresh memory,
so a one-page shell can start a three-page program without a copy of
itself in between.
