#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The MSX-DOS layer is two images (src/leg/leg.asm): what page 3 holds,
# and the body, which page 2 shows only while a file function runs. Code
# in page 3 runs with the program's own page 2 in view as often as not, so
# it may name nothing of the body's but through the door: the dispatch
# tables' handlers, lb_call, leg_entry, the doors of legc.asm, which
# are dw lines too, and the lend's three routines, which leg_ldoor and
# leg_wboot hand to the door by address. The assembler cannot say so —
# every label resolves — and a slip works until a program's page 2 holds
# something else; so the sources are read here. The body's labels are those
# its files define, and the variables laid out after its image; the page-3
# sources are leg.asm up to the body's OUTPUT line, legh.asm and legc.asm.
set -eu
cd "$(dirname "$0")/.."
awk '
function labels(file,    line, m) {
    while ((getline line < file) > 0)
        if (match(line, /^[A-Za-z_][A-Za-z0-9_]*/)) body[substr(line, 1, RLENGTH)] = 1
    close(file)
}
BEGIN {
    labels("src/leg/legb.asm"); labels("src/leg/legf.asm"); labels("src/leg/legk.asm"); labels("src/leg/legl.asm"); labels("src/leg/legi.asm")
    body["leg_rec"] = body["leg_env"] = body["leg_once"] = 1
    # the variables after the body image: leg_bss lines past legb_end
    past = 0
    while ((getline line < "src/leg/leg.asm") > 0) {
        if (line ~ /^lbss_at[ \t]*=[ \t]*legb_end/) past = 1
        if (past && match(line, /leg_bss[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
            v = substr(line, RSTART, RLENGTH); sub(/leg_bss[ \t]+/, "", v); body[v] = 1
        }
    }
    close("src/leg/leg.asm")
    bad = 0
    n = split("src/leg/leg.asm src/leg/legh.asm src/leg/legc.asm", files, " ")
    for (i = 1; i <= n; i++) {
        f = files[i]; ln = 0
        while ((getline line < f) > 0) {
            ln++
            if (line ~ /OUTPUT[ \t]+"build\/legb\.bin"/) break
            code = line; sub(/;.*/, "", code)
            if (code ~ /^[ \t]*dw[ \t]/) continue            # the dispatch tables
            sub(/^[A-Za-z_][A-Za-z0-9_]*:?/, "", code)       # a definition is not a use
            while (match(code, /[A-Za-z_][A-Za-z0-9_]*/)) {
                t = substr(code, RSTART, RLENGTH); code = substr(code, RSTART + RLENGTH)
                if ((t in body) && t != "lb_call" && t != "leg_entry" && t != "ll_lend" && t != "ll_unlend" && t != "ll_back") {
                    printf "check-leg: %s:%d: page 3 names %s, which is the body'"'"'s\n", f, ln, t > "/dev/stderr"
                    bad = 1
                }
            }
        }
        close(f)
    }
    if (!bad) print "check-leg: page 3 names nothing of the body'"'"'s"
    exit bad
}'
