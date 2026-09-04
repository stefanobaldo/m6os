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
