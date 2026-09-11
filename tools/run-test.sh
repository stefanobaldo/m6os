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

# The host's FAT checker: dosfstools' on Linux, the BSD one on macOS. A
# test that ships fsck needs one.
FSCK=""
for c in fsck.fat /sbin/fsck_msdos fsck_msdos; do
    if command -v "$c" > /dev/null 2>&1; then FSCK=$c; break; fi
done
if [ -f "tests/$name/fsck" ] && [ -z "$FSCK" ]; then
    echo "run-test: $name: no FAT checker (fsck.fat or fsck_msdos) on this host" >&2
    exit 2
fi

# le32 <file> <offset>, byte <file> <offset>: a little-endian word and a
# byte of the file, in decimal.
le32() { od -An -tu4 -j "$2" -N 4 "$1" | tr -d ' \n'; }
byte() { od -An -tu1 -j "$2" -N 1 "$1" | tr -d ' \n'; }

# check_volume <image> <first sector> <sectors>: the volume carved out and
# handed to the checker, which must find nothing to fix; then the copies
# of its table, which must be identical.
check_volume() {
    ci_vol="build/$name.$machine.$run.vol"
    dd if="$1" of="$ci_vol" bs=512 skip="$2" count="$3" 2> /dev/null
    if ! "$FSCK" -n "$ci_vol" > "$ci_vol.log" 2>&1; then
        echo "run-test: $name: $FSCK finds errors on $(basename "$1") sector $2:" >&2
        cat "$ci_vol.log" >&2
        exit 1
    fi
    # The checker's own step titles name orphans and truncation; what is
    # matched here is a finding, not a title.
    if grep -ci_i -E 'differ|lost|found orphan|orphaned|shared|truncating|is bad|wrong|corrupt|reclaim|unused' "$ci_vol.log" > /dev/null; then
        echo "run-test: $name: $FSCK complains about $(basename "$1") sector $2:" >&2
        cat "$ci_vol.log" >&2
        exit 1
    fi
    ci_rsvd=$(od -An -tu2 -j 14 -N 2 "$ci_vol" | tr -d ' \n')
    ci_nfats=$(byte "$ci_vol" 16)
    ci_fatsz=$(od -An -tu2 -j 22 -N 2 "$ci_vol" | tr -d ' \n')
    ci_k=1
    while [ "$ci_k" -lt "$ci_nfats" ]; do
        dd if="$ci_vol" of="$ci_vol.fat0" bs=512 skip="$ci_rsvd" count="$ci_fatsz" 2> /dev/null
        dd if="$ci_vol" of="$ci_vol.fat$ci_k" bs=512 skip=$((ci_rsvd + ci_k * ci_fatsz)) count="$ci_fatsz" 2> /dev/null
        if ! cmp -s "$ci_vol.fat0" "$ci_vol.fat$ci_k"; then
            echo "run-test: $name: the FAT copies 0 and $ci_k differ on $(basename "$1") sector $2" >&2
            exit 1
        fi
        ci_k=$((ci_k + 1))
    done
    echo "  $(basename "$1") sector $2: $FSCK clean, $ci_nfats FAT copies identical"
    rm -f "$ci_vol" "$ci_vol.log" "$ci_vol.fat"*
}

# check_image <image>: every volume of it — the four primary entries in
# order, a type 05h or 0Fh entry's chain of logical partitions, or, with no
# partition table of ours, the image as one volume.
check_image() {
    ci_img=$1
    ci_total=$(( $(wc -c < "$ci_img") / 512 ))
    ci_seen=0
    ci_i=0
    while [ "$ci_i" -lt 4 ]; do
        ci_e=$((446 + 16 * ci_i))
        ci_t=$(byte "$ci_img" $((ci_e + 4)))
        ci_f=$(le32 "$ci_img" $((ci_e + 8)))
        ci_c=$(le32 "$ci_img" $((ci_e + 12)))
        case $ci_t in
            1|4|6|14)
                check_volume "$ci_img" "$ci_f" "$ci_c"; ci_seen=1 ;;
            5|15)
                ci_ext=$ci_f; ci_ebr=$ci_f; ci_n=0
                while :; do
                    ci_b=$((ci_ebr * 512 + 446))
                    ci_t0=$(byte "$ci_img" $((ci_b + 4))); ci_f0=$(le32 "$ci_img" $((ci_b + 8))); ci_c0=$(le32 "$ci_img" $((ci_b + 12)))
                    case $ci_t0 in 1|4|6|14) check_volume "$ci_img" $((ci_ebr + ci_f0)) "$ci_c0"; ci_seen=1 ;; esac
                    ci_t1=$(byte "$ci_img" $((ci_b + 16 + 4))); ci_f1=$(le32 "$ci_img" $((ci_b + 16 + 8)))
                    ci_n=$((ci_n + 1))
                    case $ci_t1 in 5|15) ;; *) break ;; esac
                    [ "$ci_n" -ge 9 ] && break
                    ci_ebr=$((ci_ext + ci_f1))
                done ;;
        esac
        ci_i=$((ci_i + 1))
    done
    if [ "$ci_seen" = 0 ]; then check_volume "$ci_img" 0 "$ci_total"; fi
    return 0
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

        # A test that ships patch.tcl wants something on the image no
        # importer writes — an attribute bit. It runs with the image
        # closed, between the import and the boot.
        if [ -f "tests/$name/patch.tcl" ]; then
            openmsx_run -script "tests/$name/patch.tcl"
        fi

        M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
            openmsx_run -ext "$ext" -ext debugdevice -hda "$M6_IMAGE" -command "$slave_cmd" \
                -script tools/harness.tcl

        # A test that ships fsck wrote to its volumes: every one of them,
        # on both images, is judged by the host's FAT checker and by a
        # comparison of the two copies of its table, with the emulator
        # gone and the images closed. Neither reads the kernel's tables:
        # what the kernel wrote is read back by rules written from the
        # specification.
        if [ -f "tests/$name/fsck" ]; then
            check_image "$M6_IMAGE"
            if [ -n "$slave" ]; then check_image "$M6_SLAVE_IMAGE"; fi
        fi
    done
done
