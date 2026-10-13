# Contributing

m6os has a single maintainer. Issues and questions are welcome. Open an issue
before writing a large pull request, so we can talk first; something found and
fixed in one sitting can go straight to a pull request.

## Issues

Paste the version, the exact command and the output rather than describing them:
a report that cannot be reproduced cannot be looked into.

The **`real-hardware`** label marks anything whose failure shows only on a real
MSX and not in the emulator: VDP and slot timing, mapper behaviour, the Nextor
driver ABI. Issues and pull requests touching those carry it. Neither CI nor a
code review can see that class of bug; only the bench can.

The maintainer reproduces, labels, and either accepts or closes with a reason.
If an issue goes quiet, say so on it.

## Ground rules

- Everything in this repository is written in English.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`), one per coherent change.
- Branches use the same vocabulary: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`,
  `chore/<slug>`, kebab-case.
- `main` is protected. Changes land by pull request with a linear history
  (rebase merge). Versions are annotated SemVer tags on `main`.
- A pull request that resolves an issue says `Closes #N` in its body.
- Every commit carries a `Signed-off-by` line (`git commit -s`), certifying the
  [Developer Certificate of Origin](https://developercertificate.org/): you wrote
  the change or otherwise have the right to submit it under this project's
  license. Pull requests with unsigned commits fail the DCO check.

## Building and testing

`make check` is the one command: it fetches every tool it needs, builds, and
runs every test. It is what CI runs on every pull request, and what a pull
request is expected to pass.

Prerequisites: `make`, a C++ compiler (sjasmplus is built from source),
`curl`, `unzip`, `xz` and `shasum`. The emulator is openMSX 21.0 with the
FBLabs SD Mapper V2 cartridge added, from the project's
[fork of openMSX](https://github.com/stefanobaldo/m6os-openmsx) (branch `m6`,
release `m6-21.0.1`, reported by the binary as `21.0-m6.1`; the cartridge
is offered upstream). On x86_64 Linux and on macOS on Apple silicon it is
fetched too. Elsewhere, build the fork's tag and copy the build into
`.tools/openmsx/` (`tools/fetch-openmsx.sh` prints the commands), or install
it with `openmsx` on `PATH`; the version is checked.

Every download is pinned by version and checksum in `tools/fetch-*.sh`. Tools
land in `.tools/` (ignored by git) and the ROMs in `tools/openmsx/systemroms/`;
`make distclean` removes both, `make clean` only the build output.

`make` alone assembles everything into `build/` and prints one
`SIZE <name> <bytes>` line per binary: the three kernel images, the product
as `build/m6.com`, `build/nextor.sys` and — once `make fetch` has put the
Nextor kernel ROM in the pool, whose driver bank it takes — the kernel ROM
`build/m6-sunriseide.rom`, the commands in `build/bin/` — each
refused above one page —
and the test programs. `tools/run-test.sh <name>` runs a single
test: it builds a disk image with the Nextor system files, the program and an
`AUTOEXEC.BAT` that runs it, boots it in headless openMSX on an MSX2 with a
128K mapper, and reads the program's verdict from memory. A test directory
holding a `product` marker boots the product itself, with every command in
`BIN/`: `M6.COM` under Nextor's system files when the marker is empty,
`NEXTOR.SYS` alone on the disk when it says `nextor.sys`, with Nextor's
own system file beside it as `MSXDOS2.SYS` when it says `nextor.sys chain`,
and the kernel ROM in the cartridge with nothing of a system's on the disk
when it says `rom`;
its `<name>.tcl` gives the verdict from the screen and from the files the run
left on the image. A test directory holding a `rom` marker — the machines
that form runs on, one per line, `m6-msx2-128k` alone when it is empty — runs a second time from the kernel ROM
with m6's own driver, with the same files, disk and checks: a test with a
`block.asm` of its own gets a ROM carrying it, a `product` test boots the
product ROM; the run's images carry `.rom` in their names, and the
`<name>.tcl` reads which form it is in from `M6_FORM`. `make check` also runs
`tools/check-version.sh`, which requires the version in `src/version.inc`
and the headings of `CHANGELOG.md` to agree, and `tools/check-headers.sh`,
which requires every source file to open with the copyright and license
header the existing ones carry. The harness's exit
code is 0 for a pass, 1 for a fail and 2 when no verdict arrived in time; its
messages go to stderr, and stdout carries what the program wrote through the
emulator's debug device. `build/<name>.lst` is the assembler listing, and
`build/<name>.err` the raw stderr of the last emulator run, before the harness
filters it.
