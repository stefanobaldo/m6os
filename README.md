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

**Status:** the first piece of system code is in: a module that finds the
Nextor driver behind a drive letter and reads and writes device sectors by
calling the driver's own entry point directly, with the Nextor kernel
bypassed. A test proves it on every change, in a headless openMSX against
the Sunrise IDE driver, on an MSX2 with a 128K memory mapper, through
`make check`. There is no kernel yet; see
[`CONTRIBUTING.md`](CONTRIBUTING.md) for how to build and test.

## Documents

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how issues, pull requests and commits work
  here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
