#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The version the product reports and the changelog must agree. The version
# is read out of src/version.inc; CHANGELOG.md must carry a heading for it,
# matched literally, brackets included — except 0.0.0, the version before
# the first tag, which is never cut and so must never be a heading.
set -eu
cd "$(dirname "$0")/.."
v=$(sed -n 's/^[[:space:]]*define[[:space:]]*M6_VERSION[[:space:]]*"\([^"]*\)".*/\1/p' src/version.inc)
[ -n "$v" ] || { echo "check-version: no M6_VERSION in src/version.inc" >&2; exit 1; }
if awk -v h="## [$v]" 'index($0, h) == 1 { f = 1 } END { exit !f }' CHANGELOG.md; then
    found=1
else
    found=0
fi
if [ "$v" = 0.0.0 ]; then
    if [ "$found" = 1 ]; then
        echo "check-version: CHANGELOG.md has a [0.0.0] heading, a version that is never cut" >&2
        exit 1
    fi
    echo "check-version: $v, no heading for it, as it must be"
else
    if [ "$found" = 0 ]; then
        echo "check-version: the program reports $v and CHANGELOG.md has no [$v] heading" >&2
        exit 1
    fi
    echo "check-version: $v, heading present"
fi
