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

At the prompt, [`docs/shell.md`](docs/shell.md) is the language and
[`docs/commands.md`](docs/commands.md) the commands: `cat`, `chmod`, `cp`,
`date`, `echo`, `false`, `grep`, `head`, `kill`, `ls`, `mkdir`, `mv`,
`ps`, `pwd`, `rm`, `rmdir`, `sleep`, `sort`, `tail`, `tee`, `tr`, `true`,
`uniq` and `wc`. `exit` at the prompt starts a fresh shell.

## Documents

- [`docs/syscalls.md`](docs/syscalls.md) — the whole interface a native program
  has to the kernel.
- [`docs/storage.md`](docs/storage.md) — what m6 does with the storage devices in
  the machine, from boot.
- [`docs/shell.md`](docs/shell.md) — the shell: its lines, pipelines,
  redirection, jobs and wildcards.
- [`docs/commands.md`](docs/commands.md) — the commands in `/bin`, one
  section each.
- [`docs/programs.md`](docs/programs.md) — what a program in a file looks like,
  what it finds when the kernel starts it, and how the commands in `/bin`
  are written.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to build and test, and how issues,
  pull requests and commits work here.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`CHANGELOG.md`](CHANGELOG.md)
- [`LICENSE`](LICENSE) — BSD-3-Clause.
