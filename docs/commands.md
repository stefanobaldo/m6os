# The commands

The programs in `/bin`, one section each: what the command does, its
options, and where it differs from the Unix command of the same name.
[`docs/shell.md`](shell.md) is the shell that runs them;
[`docs/programs.md`](programs.md) is how one is written.

## What they have in common

Every command fits one 16K page, code and data. Options are single
letters after `-`, grouped or not (`wc -lw`, `wc -l -w`); an option that
takes a value takes the rest of its word or the next one (`head -n5`,
`head -n 5`); `--` ends the options. An unknown option prints the
synopsis — `head: usage: head [-n N] [file...]` — and the command ends
with status 2.

A command that takes files reads its input when given none; there is no
`-` for it. A file that fails is reported on the message output as
`name: file: ERRNO` — `cat: /t/nofile: ENOENT` — where `name` is the
word the shell was given and `ERRNO` one of the names in
[`docs/syscalls.md`](syscalls.md), *Errors*; the command goes on to the
next file and ends with status 1 if any failed.

Names are what a PC would write: up to 255 characters, matched without
regard to case and shown as written; one that fits eight characters, a
dot and three is stored short, any other with the long-name entries a PC
writes and a short alias (`MYDOCU~1.TXT`) that names it too. A name with
`" * / : < > ? \ |` or a character outside ASCII, or ending in a dot or
a space, cannot be made (`EINVAL`).

## cat

`cat [file...]` — the files, one after the other, to the output. Each
block read is written at once, so `cat` at the keyboard echoes each line
as it is typed.

## chmod

`chmod [+-][rhsa]... file...` — the attributes of each file: `r`
read-only, `h` hidden, `s` system, `a` archive; `+` sets the letters
that follow it and `-` clears them, and several such words may precede
the files (`chmod +r -a note.txt`). `+r` is the only protection m6 has:
a read-only file cannot be written, renamed or removed until `-r`. A
directory's attributes can be changed the same way; its directory bit
stays. These are FAT's attributes, not Unix's modes: there are no owners
and no execute bit.

## clear

`clear` — clears the screen and puts the cursor at the top left. It
writes one form feed (byte 12), which the console takes as clear and
home; sent to a file or a pipe, the byte goes there like any other. At
the prompt, ^L or SHIFT+HOME clears the screen without it, keeping the
line being typed.

## cp

`cp src dst` copies one file onto a new or existing name; `cp src... dir`
copies each source into the directory under its own name, and so does
`cp src dir` when `dst` is a directory. A source that is a directory is
`EISDIR`; with more than one source the destination must be a directory
(`ENOTDIR`). The copy is written in rounds of 4 KB; nothing is preserved
from the source — the copy has the archive bit and the time of the copy.
A file cannot be copied onto itself (`EBUSY`: it is open for reading).

## date

`date` — the clock, as `YYYY-MM-DD HH:MM:SS`. The kernel hands the date
and time over as a FAT entry keeps them, with the seconds halved, so the
seconds printed are always even. A machine without a real-time clock,
or one whose battery has gone, prints `1980-01-01 00:00:00`. `date` only
reads the clock; there is no way to set it from m6.

## dos

`dos path [args...]` — runs an MSX-DOS 2 program, a `.COM` file, with the
machine to itself, and returns when it ends; its MSX-DOS termination code
is the status. A path whose last component has no dot and is not found is
tried with `.com` appended. The arguments become the program's command
tail, at most 127 bytes. [`docs/dos.md`](dos.md) is what the program
finds, and what of MSX-DOS 2 is there. The shell runs a command word
ending in `.com` through `dos` by itself.

## echo

`echo [-n] word...` — the words separated by one blank and a newline,
which `-n` leaves out. Only a first word that is exactly `-n` is an
option.

## false

`false` — nothing, with status 1.

## grep

`grep [-vn] pattern [file...]` — the lines that hold the pattern, one
per line as they are; `-v` prints the lines that do not, `-n` puts each
line's number and a colon before it. With more than one file the file's
name and a colon precede each line. The pattern is a string of bytes,
matched anywhere in the line: there are no regular expressions, no `-i`
and no `-c`. An empty pattern matches every line. A line longer than
1 KB is cut there and the rest dropped.

The status is 0 when a line was selected, 1 when none was, and 2 when a
file could not be read — the Unix statuses, rather than the 1 the other
commands end with when a file fails, because 1 already means "no match".

## head

`head [-n N] [file...]` — the first `N` lines of each file, 10 without
`-n`. With more than one file, `==> file <==` precedes each and a blank
line separates them. A line of any length is printed whole.

## kill

`kill [-sig] pid...` — the signal to each process named by its pid:
`-2`, `-9`, `-13`, `-15`, or `-INT`, `-KILL`, `-PIPE`, `-TERM`; `SIGTERM`
without one. The pid of a background job is what the shell printed as
`[pid]` when it started it, and `ps` lists every process. A pid the
kernel refuses is reported — `kill: 7: ESRCH` for a process that does
not exist, `EPERM` for process 0, `EINVAL` for a pid past 15 — and the
next follows. A process that has exited and is not yet reaped takes the
signal silently, as Unix has it.

## ls

`ls [-l] [path...]` — the entries of each directory, sorted by name,
one per line, `.` and `..` left out and hidden entries included; the
current directory without a path. A path that names a file lists that
file; more than one path prints `path:` before each listing and a blank
line between them. `/mnt` lists the mounted volumes.

`-l` puts three columns before the name: the attributes as `drhsa` —
directory, read-only, hidden, system, archive — with `-` for each that
is clear; the size in bytes, 0 for a directory; and the modification
time, `YYYY-MM-DD HH:MM`, as the entry holds it.

```
----a          8 2026-09-15 14:02 note.txt
d----          0 2026-09-15 14:01 sub
```

The table holds about five hundred entries, more than a FAT16 root
directory can; a directory with more is listed as far as the table goes
and then reported — `ls: dir: too many entries` — with status 1. There
are no columns, no `-a`, and no sorting by time or size.

## mkdir

`mkdir dir...` — each directory made, empty, in a parent that exists.
There is no `-p`.

## more

`more [file...]` — the files, one after the other, to the output, stopping
each time a screenful has gone by, since the screen keeps nothing that
scrolls off its top: `ls -l | more`. After 23 rows it shows `--More--` on
the last one and waits for a key — SPACE for the next screenful, RET for
one more line, `q` to stop there. A line longer than 80 columns counts as
the rows it takes, TABs included; the prompt is erased before the output
goes on.

The keys are read on the message output, the console, so `more` pages its
input from a pipe as well as from a file. With its messages sent to a file
(`2> file`) there is no terminal to ask, and `more` copies everything
without stopping, as `cat` does. Several files follow one another with no
header between them, and there is no searching or going back.

## mv

`mv old new` renames a file or a directory, within one volume — into
another directory of the same volume as well; a file may take an
existing file's name, whose contents are then gone. `mv old... dir`
moves each source into the directory under its own name, and so does
`mv old dir` when `new` is a directory. Across volumes `mv` reports
`EXDEV` and copies nothing: `cp` and `rm` do that.

## ps

`ps` — every process, one per line under `PID PPID ST PG`: its pid, its
parent's pid (`-` for process 0, which has none), its state as a letter,
and its pages. The letters: `R` runnable or running, `W` in `wait`, `Z`
exited and waiting to be reaped, `K` reading the keyboard, `V` in
`vfork`, `P` blocked on a pipe, `S` in `sleep`.

```
PID PPID ST PG
  0    -  W  0
  1    0  W  1
  2    1  R  1
```

The kernel keeps no command name, so `ps` shows none: a process is told
apart by its pid, which the shell prints for every background job. A
background job that has ended stays `Z` only until its shell reads its
next line, or at the prompt shows its next prompt.

## pwd

`pwd` — the current directory, as the shortest path that reaches it:
`/` for the boot volume's root, `/mnt/b/dir` on another volume.

## rm

`rm file...` — each file removed. A directory is `EISDIR`, whatever it
holds: `rmdir` removes an empty one, and there is no `-r`. A read-only
file is `EACCES` until `chmod -r`; an open file is `EBUSY`.

## rmdir

`rmdir dir...` — each directory removed, provided it holds nothing.
One that does is `ENOTEMPTY`; a volume's root, or the current directory
of some process, cannot be removed.

## sleep

`sleep N` — nothing, for `N` whole seconds: `N` times 60 ticks of the
kernel's clock, asked for in pieces of at most 65 535 ticks so that no
second is rounded. ^C ends it at once.

## sort

`sort [file...]` — the lines of the files, or of the input, in byte
order: capitals before small letters, digits before both, and no
keys, no `-r`, no `-n` and no `-u` (`sort | uniq` does the last).
Everything is read into the program's one page before a line is
written: what fits is about 13 KB of text, some 550 lines of typical
length, and an input past that ends with `sort: input too large`,
status 1, and nothing printed. Lines are sorted by a merge sort of
pointers, so a full page takes about half a second on an MSX at 3.58
MHz.

## tail

`tail [-n N] [file]` — the last `N` lines, 10 without `-n`, of one file
or of the input. A file is read from its end, so `tail` of a large file
costs a few sectors, not the whole file. The input — a pipe, or the
keyboard — cannot be read backwards: `tail` keeps the last 4 KB of it
and prints the last `N` lines of those, so a line more than 4 KB back
from the end is gone.

## tee

`tee [-a] file...` — the input to the output and into each file, at
most five; `-a` adds to the files instead of emptying them first. Each
block read goes to the output at once, so a line typed at the keyboard
comes back as it is typed; the files are written from a 4 KB buffer,
when it fills and at the end, so that a large input costs each file
sixteen writes per 64 KB rather than one per block — which also means
a file trails the output by up to 4 KB until the input ends. A file
that cannot be opened is reported and skipped, status 1 at the end;
the others are written.

## tr

`tr set1 set2` — the input to the output with each byte of `set1`
replaced by the byte at the same place in `set2`, every other byte as it
is. `a-z` in a set stands for the range; `\n`, `\t` and `\\` for the
newline, the tab and the backslash, and a `\` before any other byte
for that byte — the shell expands nothing inside quotes, so this is how
a newline is named: `tr '\n' ' '`. A `set2` shorter than `set1` repeats
its last byte for the rest; a longer one has its excess ignored. There
is no `-d` and no `-s`.

## true

`true` — nothing, with status 0.

## uniq

`uniq [file]` — the lines of the file, or of the input, with each run of
equal adjacent lines printed once; `sort | uniq` collapses the equal
lines of any input. There is no `-c` and no `-d`. A line longer than
1 KB is cut there and the rest dropped.

## wc

`wc [-lwc] [file...]` — the lines, words and bytes of each file, in
that order whatever the order of the options, each right-aligned in
seven columns, then the name; all three without options; a `total`
line after more than one file. A word is a run of bytes that are not
blank, tab, newline or carriage return.
