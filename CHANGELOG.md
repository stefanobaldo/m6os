# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been distributed yet and no version has been tagged, so there is
nothing yet to have changed: every entry sits under `[Unreleased]`, under
`Added`, and together they describe what the first release will contain.
`0.1.0-rc.N` is the code being qualified once there is something to qualify;
`0.1.0` is cut after it has been, and is the first version anyone else is meant
to install.

## [Unreleased]

### Added

- Taking the machine from Nextor. A program started under Nextor records what it
  needs about the machine and its storage drivers, then replaces the Nextor
  kernel: the top page of memory below the drivers' work areas, the interrupt
  vector and the memory mapper become m6's. The cartridge's Nextor 2 driver is
  still called directly for every sector afterwards; Nextor 2 drivers only.
- Memory. The kernel finds every memory mapper in the machine and allocates 16K
  segments of the one it runs in, never handing out a segment that does not
  exist or was already in use when it started. A `mem=<K>` argument caps the
  usable memory of that mapper — `mem=128` reproduces a 128K machine on a
  larger one.
- Processes. Up to fifteen at once, switched round-robin at the 60 Hz tick with
  every register saved; a process the tick finds inside a system call gives the
  CPU up when the call returns, so no process holds the machine by staying in
  the kernel. A process owns pages 0–2, starts at `0100h` and keeps
  its stack at the top of its highest page; its memory is returned when it
  exits. `spawn` creates a child, `wait` blocks until one exits and reaps it,
  `yield` gives the CPU up early; a child that outlives its parent reaps
  itself. `fork` and `vfork` exist for portability with programs that expect
  them.
- System calls, through a fixed jump table a program calls directly:
  `exit`, `read`, `write`, `open`, `close`, `lseek`, `stat`, `readdir`,
  `chdir`, `exec`, `spawn`, `wait`, `yield`, `fork`, `vfork`, `getpid` and
  `sysconf`. Errors are Seventh Edition error numbers; every entry that is not
  implemented answers `ENOSYS`. See [`docs/syscalls.md`](docs/syscalls.md).
- Console and keyboard. The kernel programs the screen for 80 columns by 24
  rows with the machine's own font, understands BS, TAB, LF, FF and CR, wraps
  at column 80, and scrolls a write of many lines once rather than line by
  line. Keys are scanned from the interrupt handler, kept until something reads
  them, repeated while held, and delivered raw through `read`, one byte per key
  with SHIFT, CTRL and CAPS LOCK applied.
- Storage. At boot the kernel asks every Nextor driver in the machine for its
  devices, reads each one's partition table — the four primary entries and the
  chain of logical partitions inside an extended one — checks every candidate's
  boot sector, and lists the volumes it will mount as `/mnt/a`, `/mnt/b`, … with
  their sizes, the boot volume marked as `/`. Underneath, a sector is addressed
  by volume, refused past the volume's end, and moved one per driver call,
  through a write-through cache of 22 sectors. The real-time clock is read as a
  FAT date and time. See [`docs/storage.md`](docs/storage.md).
- Files. Every mounted volume is read as a FAT12 or FAT16
  filesystem: paths with `/`, `.` and `..`, long names read and written the
  way a PC does them — up to 255 characters, their case kept, a short alias
  such as `MYDOCU~1.TXT` beside each — matched without regard to case, a
  current directory per process, and eight file descriptors per process
  inherited by its children. A whole sector read into a buffer on a
  256-byte boundary goes from the driver straight into the program's memory, so
  sequential reads run at the driver's speed.
- Running a program from a file. `exec` replaces a process's image with a
  program read from a file and hands it its arguments; a file without m6's
  six-byte header is refused with `ENOEXEC`. See
  [`docs/programs.md`](docs/programs.md).
- Writing files. `open` takes `O_WRONLY`, `O_RDWR`, `O_CREAT`, `O_TRUNC` and
  `O_APPEND`; `write` puts bytes in a file, extends it, and fills with zeros a
  gap left by `lseek` past the end; `unlink`, `mkdir`, `rmdir` and `rename`
  (within a volume) join the system calls. Every call finishes on the disk
  before it returns — data, then both copies of the allocation table, then the
  directory entry — so a card can be pulled after any call and a FAT checker
  finds at worst a cluster nobody owns. A file has one writer at a time and
  cannot be removed while open; the read-only attribute is honoured; the
  modification time comes from the real-time clock. Whole sectors from a
  buffer on a 256-byte boundary go straight from the program's memory to the
  driver. The test suite writes to FAT12 and FAT16 volumes and hands the
  images to the host's FAT checker afterwards.
- Pipes. `pipe` makes one and returns its two ends as descriptors; bytes go
  in at the write end and come out at the read end in order, 256 at a time
  at most, with the writer blocking while the pipe is full and the reader
  while it is empty. A read at the end of a pipe nobody writes any more
  returns 0; a write to a pipe nobody reads any more ends the writer with
  status 141, as `SIGPIPE` does. Four pipes at once.
- Processes from files. `spawnv` creates a process from a program in a
  file in one call — fresh memory, the arguments, and the child's
  descriptors 0, 1 and 2 chosen by the caller from its own, so that
  redirection and pipes need no `dup2`, and the signals it takes by default
  though the caller ignores them — and returns the child's pid.
  `waitpid` waits for one child by name, or for any, and with `WNOHANG`
  does not block. See [`docs/syscalls.md`](docs/syscalls.md).
- `sleep` for a number of ticks; `time`, the real-time clock as a FAT
  date and time; `getcwd`, the current directory as a path; `chmod`, the
  read-only, hidden, system and archive attributes of a file — the one
  way to clear a read-only bit from m6; `procinfo`, a process's row of the
  kernel's tables for tools that ship with the kernel.
- Line editing on the keyboard. `read` from the keyboard returns whole
  lines by default, echoed as they are typed and edited with a cursor
  that moves inside the line: LEFT and RIGHT, HOME and ^E, characters
  inserted at the cursor, BS and DEL rubbing out before and under it, ^U
  the whole line, TAB kept, ^L the screen cleared with the prompt and the
  line written again at the top, ^D the end of input; `ttymode` switches
  to the raw byte-per-key reading of before, for a program that draws
  its own screen, and back. The mode is the terminal's, not a process's.
  A third mode, for a program with a history of lines, reports UP and
  DOWN to the reader and keeps the line open; `ttyline` replaces it.
- Signals. ^C or STOP ends the program in the foreground — every process
  that does not ignore `SIGINT`, so a shell ignores it and the commands
  it runs do not — and discards what was typed ahead of it; `kill` sends
  `SIGINT`, `SIGTERM`, `SIGKILL` or `SIGPIPE` to a process by pid,
  `signal` makes a process ignore one, and a child inherits that unless
  `spawnv` is asked to give it the default, which is how a shell keeps
  ignoring ^C while the command it starts does not. A
  signal ends a process at the end of the system call it is in, never
  inside it; a process that ignores `SIGPIPE` gets `EPIPE` from a write
  to a pipe nobody reads, instead of ending. A process a signal ended
  reports 128 plus the signal to `wait`.

- Booting to a shell. `M6.COM`, started under Nextor, prints its version,
  takes the machine over and boots the kernel; the kernel then runs
  `/etc/rc` through the shell if that file exists, and starts a shell at
  the keyboard, and another when that one exits. `M6 mem=<K>` caps the
  memory. See [`README.md`](README.md), *Running m6*.
- The shell, `sh`: words with `'...'` and `"..."`, `#` comments, pipelines
  of up to four commands, `<`, `>`, `>>` and `2>`, `;` lists, `&` jobs
  reported as they end, `*` and `?` over the names in a directory, `cd`
  and `exit`; a command's non-zero status printed as `[N]`; `sh -i` for
  the prompt and `sh < file` for a script. Commands are the programs in
  `/bin`. At the prompt, UP and DOWN bring back the last sixteen lines
  run, to edit and run again. See [`docs/shell.md`](docs/shell.md).
- The first commands: `echo`, `cat`, `wc`, `true` and `false`, each in one
  16K page, with the library under `src/lib/` that the rest are written
  with — buffered input and output, arguments and options, and messages
  in one form, `name: file: ENOENT`. See [`docs/programs.md`](docs/programs.md),
  *Writing a utility*.
- The file commands: `ls` (sorted, `-l` for attributes, size and time),
  `cp` (onto a name or into a directory, several at once), `mv` (within a
  volume, into a directory as well), `rm`, `mkdir`, `rmdir`, `chmod` (the
  FAT attributes by letter, `+r` the one protection there is), `pwd`,
  `head` and `tail` (`-n N`; `tail` reads a file from its end). See
  [`docs/commands.md`](docs/commands.md), which describes every command.
- The text and process commands: `grep` (a literal pattern, `-v`, `-n`),
  `sort` (byte order, what fits in its page), `uniq`, `tr` (ranges and
  `\n`), `tee` (`-a`; the files written in 4 KB pieces), `date`, `sleep`,
  `ps` (pid, parent, state and pages of every process) and `kill` (by
  number or name, `SIGTERM` by default). With these, every command in
  `/bin` is described in [`docs/commands.md`](docs/commands.md).
- `clear`, which clears the screen and homes the cursor. ^L, or SHIFT+HOME,
  does the same while a line is being typed, and writes the prompt and the
  line so far again at the top.
- `more`, which stops a listing or a file each time a screenful has gone by
  and goes on with SPACE, RET or `q` — `ls -l | more`. For it, `read` on the
  console now takes from the keyboard, so a program whose input is a pipe
  can still read what is typed.
- MSX-DOS 2 programs. `dos name.com [args]` runs a `.COM` program with the
  machine to itself — the MSX-DOS 2 layout around it, a 55.8K TPA whose
  top is where Nextor puts it at its prompt, the BIOS live, the mapper
  support routines — and hands the machine back when
  it ends, its termination code the status; a command word ending in
  `.com` runs through `dos` by itself. The console functions, the mapper
  support, and the file, directory, drive, search, process and environment
  functions of MSX-DOS 2 are served over m6's files: the mounted volumes
  are the drives, the program sees every file by its 8.3 name, and its
  errors are MSX-DOS 2's. The CP/M-compatible file functions — an FCB
  opened, made, closed, searched for, deleted and renamed, its records
  read and written in sequence, at random and in blocks, its size asked
  and set — work on the same files, so programs written for MSX-DOS 1
  and CP/M, the M80 assembler and L80 linker among them, run. Six system
  calls come with it: `segalloc` and `segfree` give a process 16K segments
  beyond its pages, `segmap` puts one into page 1 or 2 and keeps it there;
  `statfs` describes a volume, `utime` sets a modification time, and
  `statl` — with a short form of `readdir`, `chdir` and `getcwd` — names
  an entry by its 8.3 alias and its place on the volume. What serves the
  file calls lives outside the TPA, in sector buffers the disk cache lends
  for the program's run, so an editor, a file manager and a music player
  that refused a smaller TPA now run, on a 128K machine with the shell
  alive. See [`docs/dos.md`](docs/dos.md).
- `ftruncate`: a file open for writing cut to a size, or grown to one
  with zeros.

### Fixed

- A shell reading a script — `/etc/rc` among them — left every background
  job it started a zombie until the script ended, and after fourteen of
  them no process could be created: every later command failed with
  `EAGAIN`. The shell now collects the jobs that ended before each line it
  reads, without reporting them.
- MSX-DOS 2 programs: a function call returned with `Z` set whatever the
  error in `A`, and a program that branches on the flags after `CALL 5`
  read a directory for ever; `ALL_SEG` answered slot 0 for the mapper and,
  with `FRE_SEG`, lost the program's `IX` and `IY`; `CALSLT` and `CALLF`
  left the wrong slot in the page when the routine they called used `IY`,
  as the SUB-ROM's do, and the machine reset; a `_READ` asked for more
  bytes than fit between its buffer and the TPA's top read nothing and
  answered `.IPARM`, where MSX-DOS 2 reads what the file has; and a
  function called with another slot switched into page 1 or 2 crashed.
- A file written when the volume's next free cluster was one whose number
  ends in `FFh` — 255, 511, and so on — came back with a cluster of the
  formatter's fill in front of its bytes and one cluster more than its
  size needs: `write` took that cluster number for the end-of-chain mark
  and started the file one cluster further on.
- Starting `M6.COM` on an MSX2 BIOS flashed a frame of garbage over the top
  of the screen: the console turned cursor blinking on before clearing the
  video memory it uses for it, where the BIOS leaves the 40-column font —
  whatever the width when `M6.COM` was started, since the machine boots at
  40 columns.
- `getcwd` — and so `pwd` and the shell's prompt — answered `ENOENT` for a
  directory whose entry lies past the first cluster of its parent: the
  cluster it was looking for was overwritten when the search moved on to
  the parent's second cluster. On a volume with 1 KB clusters that was
  every directory after the first thirty entries of its parent.
- A program whose last sector was not a whole one, started by `exec` from
  a `vfork` child, had that sector written into the parent's memory rather
  than its own.
- A `wait` made while every child was blocked ran in a loop instead of
  idling, and could leave the kernel's count of runnable processes wrong.
- A `read` from a file or the keyboard, `readdir`, `stat` or `getcwd`
  given a buffer that reached the kernel's page overwrote the kernel; it
  is refused with `EFAULT`.
