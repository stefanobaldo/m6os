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

m6 is under active development and has not been released yet. The kernel
boots from a Nextor volume to a shell, runs processes and pipelines of the
commands in `/bin`, and reads and writes FAT12 and FAT16 volumes; the
documents below describe what exists today.

## Running m6

m6 boots from a Nextor volume, in place of the MSX-DOS 2 shell. On a card or
disk that already boots Nextor, put:

- `M6.COM` in the root — `make` builds it as `build/m6.com`;
- the commands in `BIN/` — `make` builds them as `build/bin/*`;
- optionally `ETC/RC`, a script the shell runs once at boot.

Then type `M6` at the Nextor prompt, or have `AUTOEXEC.BAT` do it. The
loader prints its version, takes the machine over, lists the volumes it
mounts and the memory it finds, runs `/etc/rc` if there is one, and gives
you a shell. `M6 mem=128` caps the memory at 128K on a larger machine.

The other way is one file in place of Nextor's own: rename the card's
`NEXTOR.SYS` to `MSXDOS2.SYS` and put m6's `NEXTOR.SYS` — `make` builds
it as `build/nextor.sys` — in its place, with `BIN/` and `ETC/RC` as
above. The Nextor kernel in the cartridge then loads m6 directly, with
nothing of the MSX-DOS 2 layer in between, and the boot is shorter by
that much. To get Nextor back, hold ESC while the machine boots, or type
`CALL SYSTEM2` at the Disk BASIC prompt: either loads `MSXDOS2.SYS`, as
the kernel itself would if m6's file were not there. A boot that fails
prints its code and loads Nextor the same way. On a card with no
`MSXDOS2.SYS`, ESC or a failed boot leaves you at the Disk BASIC prompt
instead. This way takes no arguments; `mem=` is `M6.COM`'s.

The third way needs no Nextor at all: m6 in the cartridge. `make fetch &&
make rom` builds `build/m6-sunriseide.rom`, a 128K ROM for a Sunrise IDE
compatible cartridge (a Carnivore2) with the Sunrise IDE driver of the
Nextor kernel ROM it fetches taken into it whole — the ROM is built on
your machine from that file and is not distributed. Flash it in place of
the Nextor kernel and put `BIN/` and `ETC/RC` on the card: no system
file, no `AUTOEXEC.BAT`. The root is the card's first FAT volume. There
is no key: the cartridge boots m6, and a boot that fails before the
kernel has the machine prints its code and leaves you in BASIC without a
disk. With another Nextor kernel in the machine the later slot wins; to
boot m6 past an internal one, hold that kernel's own disable key while
the machine starts (`C` for slot 3-2, the OCM's).

The same ROM is built for the SD Mapper, the ASCII16 cartridge an
MSX-Pico+ presents: `make rom-from DRIVER_ROM=<file>` takes the Nextor
kernel ROM built for that cartridge — the one its firmware embeds, or the
one it ships with — and writes `build/m6-<name>.rom` with that ROM's bank
switch and its driver taken whole. In an MSX-Pico+ the file replaces the
Nextor ROM in the firmware's system-ROM image and is flashed with it; the
card needs no system file, as above. A real FBLabs SD Mapper V2 takes the
same build from its own kernel ROM; it has not been tried on hardware.
Either way the ROM is built from a kernel ROM you already have, on your
machine, and is not distributed. `make rom` also writes
`build/m6-ascii16-test.rom`, built from Nextor's standalone ASCII16
kernel for the tests: it has no storage driver and boots no further than
a kernel with no volume, so it is not the ROM to flash. An input named
like either ROM `make rom` writes is refused; rename it.

An MSX-DOS 2 program on the card runs with `dos name.com`, or by its name
alone when it ends in `.com`, and hands the machine back when it ends:
[`docs/dos.md`](docs/dos.md) says what it finds.

At the prompt, [`docs/shell.md`](docs/shell.md) is the language and
[`docs/commands.md`](docs/commands.md) the commands: `cat`, `chmod`,
`clear`, `cp`, `date`, `dos`, `echo`, `false`, `grep`, `head`, `kill`, `ls`,
`mkdir`, `more`, `mv`, `ps`, `pwd`, `rm`, `rmdir`, `sleep`, `sort`, `tail`,
`tee`, `tr`, `true`, `uniq` and `wc`. `exit` at the prompt starts a fresh shell.

## Documents

- [`docs/syscalls.md`](docs/syscalls.md) — the whole interface a native program
  has to the kernel.
- [`docs/storage.md`](docs/storage.md) — what m6 does with the storage devices in
  the machine, from boot.
- [`docs/shell.md`](docs/shell.md) — the shell: its lines, pipelines,
  redirection, jobs and wildcards.
- [`docs/commands.md`](docs/commands.md) — the commands in `/bin`, one
  section each.
- [`docs/dos.md`](docs/dos.md) — running MSX-DOS 2 programs, and what they
  find.
- [`docs/programs.md`](docs/programs.md) — what a program in a file looks like,
  what it finds when the kernel starts it, and how the commands in `/bin`
  are written.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to build and test, and how issues,
  pull requests and commits work here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
