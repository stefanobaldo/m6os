#!/bin/sh
# Run one test: tools/run-test.sh <name>, with tests/<name>/<name>.asm built
# to build/<name>.com and the tools fetched. For each machine the test runs
# on — tests/<name>/machines, one name per line; m6-msx2-128k alone without
# that file — builds build/<name>.<machine>.dsk (Nextor system files, the
# program, an AUTOEXEC.BAT that runs it) in two openMSX runs, then boots it
# under the harness. Exit code is the first failing harness's, else 0.
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

# openMSX's Linux build probes the ALSA sequencer for MIDI ports whenever it
# builds its pluggables: the call is compiled in (PluggableFactory, guarded by
# COMPONENT_ALSAMIDI) with no runtime switch, so on a machine with no
# sequencer -- every CI runner -- libasound and then openMSX each print one
# line about it. Nothing here uses MIDI. Drop those two lines and nothing
# else: only the alsa-lib source line number and the strerror text are left
# loose, so an alsa-lib update puts the noise back in the log instead of
# silently widening what the filter hides. stderr is collected first so
# openMSX's exit status survives, which a pipeline would replace with grep's.
openmsx_run() {
    status=0
    "$OPENMSX" -machine "$machine" -setting tools/openmsx/settings.xml \
        -command "set renderer none" "$@" 2> "build/$name.$machine.err" || status=$?
    grep -v \
        -e '^ALSA lib seq_hw\.c:[0-9]*:(snd_seq_hw_open) open /dev/snd/seq failed: ' \
        -e '^error: Could not open sequencer: ' \
        "build/$name.$machine.err" >&2 || :
    return $status
}

machines=m6-msx2-128k
[ -f "tests/$name/machines" ] && machines=$(cat "tests/$name/machines")

for machine in $machines; do
    echo "  machine $machine"
    export M6_IMAGE="$ROOT/build/$name.$machine.dsk" M6_STAGING="$ROOT/$staging"
    export M6_EXPORT="$ROOT/build/$name.$machine.export"
    M6_STEP=create openmsx_run -script tools/mkdisk.tcl
    M6_STEP=import openmsx_run -ext m6-sunriseide-nextor -hda "$M6_IMAGE" -script tools/mkdisk.tcl

    M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
        openmsx_run -ext m6-sunriseide-nextor -ext debugdevice -hda "$M6_IMAGE" \
            -script tools/harness.tcl
done
