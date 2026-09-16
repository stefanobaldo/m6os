#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# Every source file opens with the three lines above, in its own comment
# syntax — ";" in assembly, "#" everywhere else — right after the #! line
# when there is one. The files are the tracked assembly, include, Tcl and
# shell sources, the Makefile and the CI workflows; test data read at run
# time and the openMSX configuration files are not looked at.
set -eu
cd "$(dirname "$0")/.."
git ls-files '*.asm' '*.inc' '*.tcl' '*.sh' Makefile '.github/workflows/*.yml' | {
    n=0
    bad=0
    while IFS= read -r f; do
        case $f in
            *.asm|*.inc) c=';' ;;
            *) c='#' ;;
        esac
        case $(sed -n 1p "$f") in
            '#!'*) first=2 ;;
            *) first=1 ;;
        esac
        got=$(sed -n "$first,$((first + 2))p" "$f")
        want="$c m6 — a Unix-like operating system for the MSX
$c Copyright (c) 2026 Stefano Baldo
$c SPDX-License-Identifier: BSD-3-Clause"
        if [ "$got" != "$want" ]; then
            echo "check-headers: $f does not open with the license header" >&2
            bad=$((bad + 1))
        fi
        n=$((n + 1))
    done
    if [ "$bad" != 0 ]; then
        echo "check-headers: $bad of $n file(s) without the license header" >&2
        exit 1
    fi
    echo "check-headers: $n file(s), header present"
}
