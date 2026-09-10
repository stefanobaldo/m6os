# m6os

**m6** (pronounced "em-six", /ˌɛmˈsɪks/) is a Unix-like operating system for the
MSX, written from scratch in Z80 assembly. It is not a port: the kernel is
designed around the MSX hardware from the first line.

It brings processes, file descriptors, pipes and a composable shell to the MSX
while staying inside the ecosystem the machine already has: FAT12/16 volumes, the
storage drivers every Nextor-compatible cartridge already carries, UNAPI for
networking, and MSX-DOS 2 `.COM` programs running unchanged in an exclusive-mode
subsystem.

Said aloud, "m6" is "MSiX": MSX + Unix. The name also points at Sixth Edition
Unix, the small, readable Unix that left Bell Labs and seeded everything after it.

**Status:** m6 takes the machine from Nextor, owns its memory, and runs a
process. A program started by Nextor records what it needs about the machine
and its drivers, then replaces the Nextor kernel: the top page of memory below
the drivers' work areas, the interrupt vector and the memory mapper become
m6's, the kernel's own RAM is overwritten, and the cartridge's storage driver
is still called directly — a sector is read and written with Nextor gone. Once
resident, the kernel finds every memory mapper in the machine by writing and
reading back — mirroring handled, so a 128K mapper is 8 segments and not
256 — and allocates 16K segments of the mapper it runs in through a
constant-time allocator that knows who owns what; a boot-time `mem=` cap
reproduces the 128K machine on a larger one. The kernel is in two parts: the
resident, one page at `C000h`, holds the hot path — slot switching, the
interrupt entry, the allocator, a text console writing straight into video
memory, the driver call, the process, the syscall table — and the cold path
lives in a second image switched into page 2 for the length of a call, the
seam a kernel in a cartridge ROM would use unchanged. A process owns pages
0–2, 48K, starts at `0100h` and calls the kernel through a fixed jump table:
`exit`, `write` to the screen, `read` from the keyboard, `getpid`, `sysconf`,
`spawn`, `wait`, `yield`, `fork` and `vfork` exist, every other entry
answers `ENOSYS`, and the kernel preserves nothing it does not return (see
[`docs/syscalls.md`](docs/syscalls.md)).
Processes run at once: the kernel keeps a table of up to fifteen, switches
between them round-robin on the 60 Hz tick — every register saved on the
process's own stack — and blocks a parent in `wait` until a child exits;
the kernel's own thread is process 0, and the memory the program that
started m6 occupied goes to the processes, so five 16K segments are free on
a 128K machine. The kernel programs the screen itself — 80 columns by 24
rows, with the machine's own font — understands the basic control codes,
scrolls a write of many lines once rather than line by line, and shows a
cursor while a process waits for a key; it scans the keyboard from the
interrupt handler, keeps what is typed before anyone reads it, repeats a
key held down, and delivers keys raw through `read`, one byte per key with
SHIFT, CTRL and CAPS LOCK applied. `fork` copies a process page by page
and `vfork` shares its memory with the child while the parent waits — the
two compatibility paths beside `spawn`. At boot the kernel asks every
Nextor driver in the machine for its devices, reads each device's partition
table — the four primary entries and the chain of logical partitions inside
an extended one, in the order Nextor itself visits them — checks every
candidate's boot sector, and lists the FAT12 and FAT16 volumes it will mount
as `/mnt/a`, `/mnt/b`, … with sizes and the boot volume marked (see
[`docs/storage.md`](docs/storage.md)); underneath, a block layer addresses a
sector by volume and refuses one past the volume's end before the driver is
touched, moves one sector per driver call so that the interrupt-disabled
region of a call stays inside one frame, reads a sector from the driver
straight into any 16K segment, and keeps a write-through cache of 24
sectors; the real-time clock is read as a FAT date and time. Eight tests prove all of this on
every change in a headless openMSX against the Sunrise IDE driver, on an
MSX2 with a 128K memory mapper — with the cartridge in a plain and in an
expanded slot — and on an MSX2 with a 4 MB mapper, where segments 128 to
255 exist, through `make check`; the third creates processes of one and
three pages and times a null syscall on each path, the fourth runs two
processes that alternate on the tick, one that never calls the kernel and
still does not stop another, a zombie, an orphan, the table and the memory
running out, and times the context switch; the fifth checks the screen row
by row and presses keys on the emulated matrix — typed ahead, held down,
too many at once, with two readers waiting — the sixth forks with and
without a copy, exercises every refusal, and times a two-page `fork`; the
seventh boots from an image with a primary partition, a chain of two
logical ones and a second device on the same interface, checks the boot
listing against the images from outside the machine, reads through the
volume-relative path and past its end, hits, misses and evicts in the
cache, writes a sector through it and reads the file back from the image,
copies a sector between segments both ways, and compares the clock with the
host's; and the eighth measures what a driver call of 1, 2, 4 and 8 sectors
costs and how many ticks it loses — a hint in the emulator, a measurement
on hardware. The block layer is in place; there is no filesystem yet. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for how to build and test.

**Hardware.** The smallest machine m6 targets — 128K of mapper memory — is
checked on every change in the emulator and on real hardware too, on an MSX2+ at
3.58 MHz whose memory mapper is reduced to 128K. Every test that runs on real
hardware runs there, and no timing moves by more than two 60 Hz ticks against
the same machine with its full 512K: the memory size decides what fits, not what
things cost. After boot, five of that machine's eight segments are free — the
kernel gives the processes the memory the program that started m6 occupied —
which is what a process of up to three pages has to fit in. Taking the machine is
verified on an MSX2+ at 3.58 MHz and on a One Chip MSX, against two Nextor 2
drivers written by different authors: Sunrise IDE 0.1.7 through a Carnivore2,
and FBLabs SDXC 1.1.0 through an MSX-Pico+. On both machines, and through both
drivers, a sector is read and written with the Nextor kernel overwritten, and
Nextor reads that sector back from the file on the next boot. One driver call
takes 4.75 ms through the Sunrise IDE and 5.30 ms through the FBLabs SDXC on the
MSX2+ at 3.58 MHz, measured by difference over 600 reads. Mapper detection
reports 8 segments on the MSX2+ reduced to 128K, 32 on the same machine with its
own 512K, and 64 with a Carnivore2 inserted — the cartridge's own mapper, with
the machine's 32 segments detected beside it and left alone — and 128 and 256
segments on the One Chip MSX at 2 MB and 4 MB, where Nextor reports 255, so
detection is verified across the whole range an 8-bit segment number can hold,
on machines that exist. The boot-time `mem=` cap has been exercised on hardware
too: capping the One Chip MSX at 2 MB down to 128K leaves the allocator refusing
every segment from 8 to 127, while detection still reports the machine as it is.
A second mapper is detected wherever it sits: an MSX-Pico+ holding 432K answers
27 segments, a count that is not a power of two. A 16K page copy by `LDIR` takes
105.48 ms on the MSX2+ at 3.58 MHz, 94.02 ms by unrolled `LDI`. A null system
call goes round in 17.29 µs when its body is in the resident page and 78.55 µs
when it is in the switched image, on the MSX2+ at 3.58 MHz — 17.35 and 78.61 µs
on the same machine reduced to 128K — measured by difference over 524 288 calls;
a process of three pages calls through the window with its stack in the page the
window takes. A context switch — save every register, pick the next process, map
its pages, restore — takes 205.26 µs on the MSX2+ at 3.58 MHz, measured by
difference over 524 288 `yield`s between two processes; two processes alternate
on the tick there, and creating processes stops with the memory out after five
on that machine and with the process table full after fifteen on the One Chip
MSX. A two-page `fork` takes 219.31 ms on the MSX2+ at 3.58 MHz, measured over 32
forks against 210.96 ms calculated from the page copy; what is typed on that
machine's keyboard reaches a process as the test expects. The block layer's
transfer path is measured on that machine through both drivers, by difference
over 2400 sector reads per point: one driver call of one sector costs 4.80 ms
through the Sunrise IDE and 5.39 ms through the FBLabs SDXC — the 4.75 and
5.30 ms measured earlier over 600 reads, to within 2 % — two sectors 7.52 and
9.66 ms per call, 3.76 and 4.83 ms a sector, and four sectors 13.00 ms per
call, 3.25 ms a sector, through the Sunrise IDE. Past that point the method
stops measuring: the figure is taken against the 60 Hz tick counter, which a
call whose interrupt-disabled region crosses a frame starves, so four sectors
through the FBLabs SDXC and eight through either driver read as a floor near
one frame rather than as a cost. What those points do say is what they lose. A
call of eight sectors loses 129 ticks of 1800 through the Sunrise IDE and 301
of 1980 through the FBLabs SDXC; one sector per call loses 2 of about 2100 on
both, and those two are the measurement's own boundary at each end rather than
the call's, a 5 ms call being unable to span a frame. One sector per call is
what the kernel issues. Every partition of both bench cards is listed with the
size Nextor's FDISK shows — including one whose file allocation table fills 256
sectors, the most a FAT16 volume can have — and on a One Chip MSX with both
cartridges inserted both drivers are found and every volume of both cards
listed. The real-time clock reads back the date and time set under Nextor on
the same machine.

## Documents

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how issues, pull requests and commits work
  here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
