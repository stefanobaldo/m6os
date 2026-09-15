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

Names are FAT short names: at most eight characters, a dot and three,
matched without regard to case and shown in lower case. A name that is
not one cannot be made (`EINVAL`).

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

## cp

`cp src dst` copies one file onto a new or existing name; `cp src... dir`
copies each source into the directory under its own name, and so does
`cp src dir` when `dst` is a directory. A source that is a directory is
`EISDIR`; with more than one source the destination must be a directory
(`ENOTDIR`). The copy is written in rounds of 4 KB; nothing is preserved
from the source — the copy has the archive bit and the time of the copy.
A file cannot be copied onto itself (`EBUSY`: it is open for reading).

## echo

`echo [-n] word...` — the words separated by one blank and a newline,
which `-n` leaves out. Only a first word that is exactly `-n` is an
option.

## false

`false` — nothing, with status 1.

## head

`head [-n N] [file...]` — the first `N` lines of each file, 10 without
`-n`. With more than one file, `==> file <==` precedes each and a blank
line separates them. A line of any length is printed whole.

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

## mv

`mv old new` renames a file or a directory, within one volume — into
another directory of the same volume as well; a file may take an
existing file's name, whose contents are then gone. `mv old... dir`
moves each source into the directory under its own name, and so does
`mv old dir` when `new` is a directory. Across volumes `mv` reports
`EXDEV` and copies nothing: `cp` and `rm` do that.

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

## tail

`tail [-n N] [file]` — the last `N` lines, 10 without `-n`, of one file
or of the input. A file is read from its end, so `tail` of a large file
costs a few sectors, not the whole file. The input — a pipe, or the
keyboard — cannot be read backwards: `tail` keeps the last 4 KB of it
and prints the last `N` lines of those, so a line more than 4 KB back
from the end is gone.

## true

`true` — nothing, with status 0.

## wc

`wc [-lwc] [file...]` — the lines, words and bytes of each file, in
that order whatever the order of the options, each right-aligned in
seven columns, then the name; all three without options; a `total`
line after more than one file. A word is a run of bytes that are not
blank, tab, newline or carriage return.
