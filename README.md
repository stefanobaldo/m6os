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

**Status:** m6 takes the machine from Nextor and owns its memory. A program
started by Nextor records what it needs about the machine and its drivers,
then replaces the Nextor kernel: the top page of memory below the drivers'
work areas, the interrupt vector and the memory mapper become m6's, the
kernel's own RAM is overwritten, and the cartridge's storage driver is still
called directly — a sector is read and written with Nextor gone. Once
resident, the kernel finds every memory mapper in the machine by writing and
reading back — mirroring handled, so a 128K mapper is 8 segments and not
256 — and allocates 16K segments of the mapper it runs in through a
constant-time allocator that knows who owns what; a boot-time `mem=` cap
reproduces the 128K machine on a larger one. What stays resident — slot
switching, the interrupt entry, a text console writing straight into video
memory, the driver call, memory — lives under `src/kernel/` and is assembled
into one image whose size the build reports, and which carries nothing but
the kernel: the programs that test it enter through a record and a jump
table. Two tests prove all of this on every change in a headless openMSX
against the Sunrise IDE driver, on an MSX2 with a 128K memory mapper — with
the cartridge in a plain and in an expanded slot — and on an MSX2 with a
4 MB mapper, where segments 128 to 255 exist, through `make check`. There is
no scheduler and no filesystem yet; see [`CONTRIBUTING.md`](CONTRIBUTING.md)
for how to build and test.

**Hardware.** The emulator holds the baseline — an MSX2 with a 128K mapper, the
smallest machine m6 targets — and real hardware holds the rest. Taking the
machine is verified on an MSX2+ at 3.58 MHz and on a One Chip MSX, against two
Nextor 2 drivers written by different authors: Sunrise IDE 0.1.7 through a
Carnivore2, and FBLabs SDXC 1.1.0 through an MSX-Pico+. On both machines, and
through both drivers, a sector is read and written with the Nextor kernel
overwritten, and Nextor reads that sector back from the file on the next boot.
One driver call takes 4.75 ms through the Sunrise IDE and 5.30 ms through the
FBLabs SDXC on the MSX2+ at 3.58 MHz, measured by difference over 600 reads.

## Documents

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how issues, pull requests and commits work
  here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
