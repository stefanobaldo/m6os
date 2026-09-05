#!/bin/sh
# Run one test: tools/run-test.sh <name>, with tests/<name>/<name>.asm built
# to build/<name>.com and the tools fetched. Builds build/<name>.dsk (Nextor
# system files, the program, an AUTOEXEC.BAT that runs it) in two openMSX
# runs, then boots it under the harness. Exit code is the harness's.
set -eu
name=${1:?usage: tools/run-test.sh <name>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ -x .tools/openmsx/bin/openmsx ]; then
    OPENMSX=.tools/openmsx/bin/openmsx
    export OPENMSX_SYSTEM_DATA="$ROOT/.tools/openmsx/share"
else
    OPENMSX=openmsx
fi
export OPENMSX_USER_DATA="$ROOT/tools/openmsx"

com="build/$name.com"
[ -f "$com" ] || { echo "run-test: $com not built; run make first" >&2; exit 2; }
upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')

staging="build/$name.staging"
rm -rf "$staging" && mkdir -p "$staging"
cp .tools/nextor/NEXTOR.SYS .tools/nextor/COMMAND2.COM "$staging/"
cp "$com" "$staging/$upper.COM"
printf '%s\r\n' "$upper" > "$staging/AUTOEXEC.BAT"

openmsx_run() {
    "$OPENMSX" -machine m6-msx2-128k -setting tools/openmsx/settings.xml \
        -command "set renderer none" "$@"
}

export M6_IMAGE="$ROOT/build/$name.dsk" M6_STAGING="$ROOT/$staging"
M6_STEP=create openmsx_run -script tools/mkdisk.tcl
M6_STEP=import openmsx_run -ext m6-sunriseide-nextor -hda "$M6_IMAGE" -script tools/mkdisk.tcl

M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
    openmsx_run -ext m6-sunriseide-nextor -ext debugdevice -hda "$M6_IMAGE" \
        -script tools/harness.tcl
