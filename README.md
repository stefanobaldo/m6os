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

m6 is under active development and has not been released yet. The kernel boots,
owns the machine's memory and runs processes, and reads files from FAT12 and
FAT16 volumes; the documents below describe what exists today.

## Documents

- [`docs/syscalls.md`](docs/syscalls.md) — the whole interface a native program
  has to the kernel.
- [`docs/storage.md`](docs/storage.md) — what m6 does with the storage devices in
  the machine, from boot.
- [`docs/programs.md`](docs/programs.md) — what a program in a file looks like,
  and what it finds when the kernel starts it.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to build and test, and how issues,
  pull requests and commits work here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
