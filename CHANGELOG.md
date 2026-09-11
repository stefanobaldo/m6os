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
  every register saved. A process owns pages 0–2, starts at `0100h` and keeps
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
  through a write-through cache of 24 sectors. The real-time clock is read as a
  FAT date and time. See [`docs/storage.md`](docs/storage.md).
- Files. Every mounted volume is read as a FAT12 or FAT16
  filesystem: paths with `/`, `.` and `..`, short names matched without regard
  to case, a current directory per process, and eight file descriptors per
  process inherited by its children. A whole sector read into a buffer on a
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
