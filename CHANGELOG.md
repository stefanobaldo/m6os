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
