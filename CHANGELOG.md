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

- Build system: `make` assembles the programs under `tests/` with sjasmplus
  1.24.0 and reports the size of every binary it produces.
- Test harness: `make check` fetches the pinned tools (sjasmplus, openMSX 21.0,
  a C-BIOS build that hosts Nextor, Nextor 2.1.4), builds a bootable disk image
  per test and runs it in headless openMSX on an MSX2 with a 128K memory
  mapper, reading the program's verdict back from memory.
- Continuous integration: `make check` runs on every pull request and on every
  push to `main`.
