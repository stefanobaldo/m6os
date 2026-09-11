#!/bin/sh
# Run one test: tools/run-test.sh <name>, with tests/<name>/<name>.asm built
# to build/<name>.com and the tools fetched. For each machine the test runs
# on — tests/<name>/machines, one name per line; m6-msx2-128k alone without
# that file — and for each argument line — tests/<name>/args, one command
# line per run, an empty line being a run without arguments; one run without
# that file — builds build/<name>.<machine>.<run>.dsk (Nextor system files,
# the program, an AUTOEXEC.BAT that runs it with the arguments) in two
# openMSX runs, then boots it under the harness. Exit code is the first
# failing harness's, else 0.
#
# The disk: tests/<name>/disk names the image's shape — line 1 the
# diskmanipulator sizes and options for the master (`2M` is one
# unpartitioned volume; `-nextor 4M 2M 2M` a Nextor partition table with a
# primary and a chain of two; `-fat16max` one FAT16 partition whose FAT is
# 256 sectors, which no formatter produces at this size), line 2, if
# present, the same for a slave device on the same interface. Without the
# file: a 2M master alone, which is what every test had before there was a
# file. The system files go on the first volume either way.
#
# Files on the volume: tests/<name>/files/, a directory tree, is copied
# into the staging directory as it is; each program built from
# tests/<name>/progs/<prog>.asm (build/<name>.progs/<prog>) is copied to
# the path tests/<name>/progs/<prog>.dest names; and tests/<name>/files.tcl,
# if present, is sourced by mkdisk.tcl before the import, with M6_STAGING
# set, to write files too large or too regular to commit.
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
# The host's offset from UTC, +hhmm, for a test that reads the RTC: the
# emulated clock keeps local time and openMSX's Tcl has no clock format.
M6_TZ_OFFSET=$(date +%z)
export M6_TZ_OFFSET

com="build/$name.com"
[ -f "$com" ] || { echo "run-test: $com not built; run make first" >&2; exit 2; }
upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')

staging="build/$name.staging"

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
# The image's shape, and the extension that goes with it: the one with a
# slave device only when the test asks for one, because openMSX creates a
# 100 MB image for a slave nobody named.
master=2M
slave=""
if [ -f "tests/$name/disk" ]; then
    master=$(sed -n 1p "tests/$name/disk")
    slave=$(sed -n 2p "tests/$name/disk")
fi
ext=m6-sunriseide-nextor
[ -n "$slave" ] && ext=m6-sunriseide-nextor-2
# The argument lines, read with their line numbers so an empty line counts.
if [ -f "tests/$name/args" ]; then
    runs=$(grep -c '' "tests/$name/args")
else
    runs=1
fi

for machine in $machines; do
    run=0
    while [ "$run" -lt "$runs" ]; do
        run=$((run + 1))
        args=""
        [ -f "tests/$name/args" ] && args=$(sed -n "${run}p" "tests/$name/args")
        echo "  machine $machine run $run${args:+ ($args)}"
        rm -rf "$staging" && mkdir -p "$staging"
        cp .tools/nextor/NEXTOR.SYS .tools/nextor/COMMAND2.COM "$staging/"
        cp "$com" "$staging/$upper.COM"
        printf '%s%s\r\n' "$upper" "${args:+ $args}" > "$staging/AUTOEXEC.BAT"
        if [ -d "tests/$name/files" ]; then
            cp -R "tests/$name/files/." "$staging/"
        fi
        for dest in "tests/$name"/progs/*.dest; do
            [ -f "$dest" ] || continue
            prog=$(basename "$dest" .dest)
            target=$(cat "$dest")
            mkdir -p "$staging/$(dirname "$target")"
            cp "build/$name.progs/$prog" "$staging/$target"
        done
        M6_FILES_TCL=""
        [ -f "tests/$name/files.tcl" ] && M6_FILES_TCL="$ROOT/tests/$name/files.tcl"
        export M6_FILES_TCL
        export M6_IMAGE="$ROOT/build/$name.$machine.$run.dsk" M6_STAGING="$ROOT/$staging"
        export M6_EXPORT="$ROOT/build/$name.$machine.$run.export"
        export M6_MASTER="$master" M6_SLAVE="$slave"
        export M6_SLAVE_IMAGE="$ROOT/build/$name.$machine.$run.slave.dsk"
        # openMSX's command line takes -hda alone; the slave's image goes
        # in through the hdb command, which runs before the machine boots.
        slave_cmd="set renderer none"
        [ -n "$slave" ] && slave_cmd="hdb $M6_SLAVE_IMAGE"
        M6_STEP=create openmsx_run -script tools/mkdisk.tcl
        M6_STEP=import openmsx_run -ext "$ext" -hda "$M6_IMAGE" -command "$slave_cmd" \
            -script tools/mkdisk.tcl
        # A test that ships mbr-ext-lba wants its extended container
        # addressed by LBA, type 0Fh, the way a partitioner writes one that
        # begins past the CHS limit. The image builder writes 05h, the CHS
        # form, because the images it makes are small; a card of a few
        # gigabytes is the other form, and only this rewrite puts it under
        # test. Entry 2 of the MBR, its type byte at 446 + 16 + 4.
        if [ -f "tests/$name/mbr-ext-lba" ]; then
            cur=$(dd if="$M6_IMAGE" bs=1 skip=466 count=1 2>/dev/null |
                  od -An -tx1 | tr -d ' \n')
            if [ "$cur" != "05" ]; then
                echo "run-test: $name: MBR entry 2 is type $cur, not 05:" \
                     "the extended container is not where this expects it" >&2
                exit 1
            fi
            printf '\017' |
                dd of="$M6_IMAGE" bs=1 seek=466 count=1 conv=notrunc 2>/dev/null
        fi

        M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
            openmsx_run -ext "$ext" -ext debugdevice -hda "$M6_IMAGE" -command "$slave_cmd" \
                -script tools/harness.tcl
    done
done
