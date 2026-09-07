# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been distributed yet and no version has been tagged, so every entry
sits under `[Unreleased]` and there is no version heading to place it under. The
crates carry `0.0.0` until then. `0.1.0-rc.N` is the code being qualified once
there is something to qualify; `0.1.0` is cut after it has been, and is the first
version anyone else is meant to install.

## [Unreleased]

### Added

- Memory (`src/kernel/mem.asm`): the resident detects every memory mapper in
  the machine by writing and reading back through page 2 — mirroring
  handled, the count kept as a word so that a 4 MB mapper reports 256
  segments where Nextor reports 255 — and allocates 16K segments of the
  mapper it runs in with a constant-time allocator: a stack of free
  segments and an owner byte per segment, so a segment is never freed by
  someone who does not own it and a process's segments can be returned as
  a whole. Segments that do not exist, lie above the boot-time cap or were
  in use when the kernel started are never handed out. The boot summary
  names every mapper found, with the primary's free count.
- A `mem=<K>` argument to the program that starts m6 caps the usable
  segments of the primary mapper — `mem=128` reproduces the 128K machine
  on a larger one. Below 128, not a multiple of 16, or not a number is
  refused before anything is touched.
- The resident image exports a jump table — console output, the driver
  call, slot switching, the allocator — and its record gains two fields: an
  address to jump to once the kernel has booted, and the cap. The image is
  now the kernel alone: a program's own code is copied above it by the
  loader and entered through the record.
- Loader module (`src/loader/takeover.asm`): the Nextor 2 kernel check and
  the takeover sequence, shared by every program that hands the machine to
  the resident.
- Test `mapper`: checks the detected count against what Nextor saw,
  allocates every free segment, writes each one at both ends and reads
  them all back distinct, frees them as a whole and allocates them again to
  prove the same segment never comes back twice, exercises the allocator's
  refusals, checks the cap, and measures a 16K page copy by `LDIR` and by
  unrolled `LDI`. Runs on the 128K machine and on a new 4 MB machine
  definition, each with and without `mem=128`; on the 4 MB machine the
  allocation walks segments 128 to 255. Also run on an MSX2+ at 3.58 MHz and
  on a One Chip MSX, where detection reports 32 segments, 64 with a Carnivore2
  inserted, and 128 and 256 at 2 MB and 4 MB — 256 where Nextor reports 255 —
  and a second mapper of 432K answers 27 segments, a count that is not a power
  of two; a 16K page copy takes 105.48 ms by `LDIR` and 94.02 ms by unrolled
  `LDI` on the 3.58 MHz machine.
- Test harness: a test may list command lines to run with
  (`tests/<name>/args`, one run per line); on a run that never reports, the
  harness prints which slot the memory scan was in.
- The resident kernel image (`src/kernel/`, built to `build/kernel.bin`, its
  size reported by the build): slot switching without the BIOS, an interrupt
  handler that acknowledges the VDP and counts the tick, a text console that
  writes straight into VRAM on the inherited SCREEN 0, the Nextor driver
  call, and a contract — a header and a capture record — for whatever puts
  the image in page 3.
- Test `takeover`: under Nextor, lists the drivers and checks each one's
  header, finds the boot drive's driver, records what the resident needs,
  creates a file and times two reference loops; then takes the machine —
  restores the hooks Nextor set, copies the image below the drivers' work
  areas, installs its interrupt vector — overwrites the Nextor kernel's
  memory, reads and writes a sector through the cartridge driver with the
  kernel gone, checks its tick against the real-time clock while doing so,
  and measures the length of one driver call. Runs on two emulated machines,
  with the cartridge in a plain and in an expanded slot; the harness checks
  the written file from outside the machine. Also run on an MSX2+ at 3.58 MHz
  and on a One Chip MSX against two Nextor 2 drivers written by different
  authors — Sunrise IDE 0.1.7 and FBLabs SDXC 1.1.0 — where one driver call
  takes 4.75 ms and 5.30 ms respectively on the 3.58 MHz machine.
- Test harness: a test may name the machines it runs on
  (`tests/<name>/machines`) and define a check of the disk image after the
  verdict; a second machine definition with both cartridge slots expanded.
- Nextor driver access (`src/nextor/`): find the driver behind a drive letter
  through Nextor's driver-information calls, then read and write device
  sectors by calling the driver's `DEV_RW` entry point directly — slot switch,
  bank switch, call — with interrupts held off for the duration of the call,
  as the Nextor kernel itself does. Nextor 2 drivers only.
- Test `drvcall`: under Nextor in openMSX, reads a sector both through Nextor
  and directly and compares them, writes a sector directly and reads it back
  through the file that owns it, and runs 600 direct reads while the timer
  keeps ticking. Its report is kept in the CI log.
- Tests may include modules from `src/`, and a test may ask the harness to
  keep its screen in the log on a pass.
- Build system: `make` assembles the programs under `tests/` with sjasmplus
  1.24.0 and reports the size of every binary it produces.
- Test harness: `make check` fetches the pinned tools (sjasmplus, openMSX 21.0,
  a C-BIOS build that hosts Nextor, Nextor 2.1.4), builds a bootable disk image
  per test and runs it in headless openMSX on an MSX2 with a 128K memory
  mapper, reading the program's verdict back from memory.
- Continuous integration: `make check` runs on every pull request and on every
  push to `main`.

### Changed

- The resident image no longer carries any test's code: the `takeover`
  test's second half runs from a block the loader copies above the image
  and calls the resident through the jump table. The build exports the
  image's end address for programs that assemble such a block.
- The Nextor driver module no longer calls the BIOS `ENASLT` or reads
  `RAMAD1` itself: the including program supplies both, so a kernel that has
  taken the machine can use its own. A program without a BDOS to call can
  leave `nx_find` out.
