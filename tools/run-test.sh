#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
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
# The forms: tests/<name>/rom, one machine per line (m6-msx2-128k alone
# when the file is empty), asks for a second form of the same test booted
# from the kernel ROM with m6's own driver — build/<name>.rom, the test's
# block in bank 2, for a test with tests/<name>/block.asm; the product
# ROM for a test whose product marker is empty — with the same files,
# programs, disk, patches and outside checks, and nothing of a system's
# on the disk. A line may start with the word `sdmapper`: that run boots
# the same test from the SD Mapper kernel ROM with m6's SD driver —
# build/<name>.sd.rom, or the product ROM build/m6-sdmapper.rom — in the
# emulated SD Mapper V2 with the disk's images as its cards; a line may
# start with `turbo` instead: the same ROM in the SD Mapper cartridge
# that presents the m6 block device and a memory mapper of its own, so
# the kernel runs the driver in Turbo; or with `fatacc`: the cartridge
# whose block offers the FAT accelerator and not Turbo; without a word
# the cartridge is the Sunrise IDE. The forms run in order, `com` then
# `rom`; the test's .tcl reads M6_FORM and M6_CART (`sunrise`,
# `sdmapper`, `turbo` or `fatacc`); the ROM form's images and logs carry
# `.rom`, `.sd.rom`, `.turbo.rom` or `.fatacc.rom` in their names
# (build/<name>.rom.<machine>.<run>.dsk).
#
# Files on the volume: tests/<name>/files/, a directory tree, is copied
# into the staging directory as it is; a test with a `product` marker
# boots the product (below) and carries every build/bin/* in BIN/; each program built from
# tests/<name>/progs/<prog>.asm (build/<name>.progs/<prog>) is copied to
# the path tests/<name>/progs/<prog>.dest names; and tests/<name>/files.tcl,
# if present, is sourced by mkdisk.tcl before the import, with M6_STAGING
# set, to write files too large or too regular to commit.
#
# tests/<name>/readonly, holding `master` or `slave`, names the image
# the emulator must open read-only — the card's write-protect switch on
# an SD Mapper, which openMSX reads off the file's permissions: the
# image is made unwritable after it is built and before the boot, and
# writable again after the run.
set -eu
name=${1:?usage: tools/run-test.sh <name>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ -x .tools/openmsx/bin/openmsx ]; then
    OPENMSX=.tools/openmsx/bin/openmsx
    export OPENMSX_SYSTEM_DATA="$ROOT/.tools/openmsx/share"
elif [ -x .tools/openmsx/openMSX.app/Contents/MacOS/openmsx ]; then
    OPENMSX=.tools/openmsx/openMSX.app/Contents/MacOS/openmsx
    export OPENMSX_SYSTEM_DATA="$ROOT/.tools/openmsx/openMSX.app/Contents/Resources/share"
else
    OPENMSX=openmsx
fi
export OPENMSX_USER_DATA="$ROOT/tools/openmsx"
# The host's offset from UTC, +hhmm, for a test that reads the RTC: the
# emulated clock keeps local time and openMSX's Tcl has no clock format.
M6_TZ_OFFSET=$(date +%z)
export M6_TZ_OFFSET

# A test with a `product` marker boots the product itself, with every
# utility in BIN/, instead of a program of its own. The marker says which
# way: empty, build/m6.com as M6.COM, run from AUTOEXEC.BAT under Nextor's
# own system files; `nextor.sys`, build/nextor.sys as NEXTOR.SYS, loaded
# by the Nextor kernel ROM with nothing else of Nextor's on the disk;
# `nextor.sys chain`, the same with Nextor's NEXTOR.SYS as MSXDOS2.SYS and
# COMMAND2.COM beside it, for a test that has the loader load Nextor — its
# AUTOEXEC.BAT comes from the test's files/; `rom`, the kernel ROM
# build/m6-sunriseide.rom in the cartridge instead of Nextor's, with no
# system file on the disk at all; `rom legacy`, the same with
# build/m6-sunriseide-legacy.rom, the Sunrise ROM with the Nextor driver
# bank and the adapter; `rom <name>`, the same with build/<name>.rom, a
# ROM the test builds for itself, in the Sunrise cartridge with its
# disk; `rom ascii16`, the ASCII16 test ROM build/m6-ascii16-test.rom as
# a plain ASCII16 cartridge with no disk behind it — no image is built or
# attached, and the test reads the kernel stopping for want of a volume;
# `rom ascii16 <name>`, the same with build/<name>.rom in the cartridge;
# `rom sdmapper`, the kernel ROM build/m6-sdmapper.rom in the emulated
# FBLabs SD Mapper V2 with the disk's images as its cards, no system file
# on them; `rom sdmapper legacy`, the same with
# build/m6-sdmapper-legacy.rom, the ROM with that cartridge's own Nextor
# driver bank and the adapter; `rom sdmapper <name>`, the same with
# build/<name>.rom, a ROM the test builds for itself; `rom turbo`, the
# kernel ROM build/m6-sdmapper.rom in the SD Mapper cartridge that also
# presents the m6 block device and a 432K memory mapper of its own, the
# disk's images as its cards, so the driver runs in Turbo; `rom
# turbo-liar`, the same ROM in a cartridge whose block offers Turbo with
# no mapper behind it; `rom turbo <name>`, the Turbo cartridge with
# build/<name>.rom; `rom fatacc`, the kernel ROM in the SD Mapper
# cartridge whose block offers the FAT accelerator and not Turbo; `rom
# fatacc <name>`, that cartridge with build/<name>.rom.
# set_form <form> <cartridge>: the product, the file booted (com), the
# name it takes on the disk (upper), and the tag the run's files carry,
# for one form on one cartridge (sunrise, sdmapper or turbo; the com
# form's is the Nextor ROM's, whatever is given).
set_form() {
    form=$1
    cart=$2
    tag=$name
    product=""
    liar=""
    [ -f "tests/$name/product" ] && product=$(cat "tests/$name/product")
    if [ "$form" = rom ]; then
        tag=$name.rom
        [ "$cart" = sdmapper ] && tag=$name.sd.rom
        [ "$cart" = turbo ] && tag=$name.turbo.rom
        [ "$cart" = fatacc ] && tag=$name.fatacc.rom
        if [ -f "tests/$name/block.asm" ]; then
            product="rom $name"
            [ "$cart" = sdmapper ] && product="rom sdmapper $name.sd"
            [ "$cart" = turbo ] && product="rom turbo $name.sd"
            [ "$cart" = fatacc ] && product="rom fatacc $name.sd"
        elif [ -z "$product" ] && [ -f "tests/$name/product" ]; then
            product=rom
            [ "$cart" = sdmapper ] && product="rom sdmapper"
            [ "$cart" = turbo ] && product="rom turbo"
            [ "$cart" = fatacc ] && product="rom fatacc"
        else
            echo "run-test: $name: the rom marker needs tests/$name/block.asm or an empty product marker" >&2; exit 2
        fi
    fi
    # own: the ROM is the test's own, not the product's — nothing of
    # build/bin/* goes to BIN/ then.
    own=""
    if [ -f "tests/$name/product" ] || [ "$form" = rom ]; then
        case $product in
            "") product=m6.com; com="build/m6.com"; upper=M6 ;;
            "nextor.sys"|"nextor.sys chain") com="build/nextor.sys"; upper=NEXTOR ;;
            "rom") com="build/m6-sunriseide.rom"; upper=M6 ;;
            "rom legacy") com="build/m6-sunriseide-legacy.rom"; upper=M6; product=rom ;;
            "rom ascii16") com="build/m6-ascii16-test.rom"; upper=M6 ;;
            "rom ascii16 "*) com="build/${product#rom ascii16 }.rom"; upper=M6; product="rom ascii16"; own=1 ;;
            "rom sdmapper") com="build/m6-sdmapper.rom"; upper=M6 ;;
            "rom sdmapper legacy") com="build/m6-sdmapper-legacy.rom"; upper=M6; product="rom sdmapper" ;;
            "rom sdmapper "*) com="build/${product#rom sdmapper }.rom"; upper=M6; product="rom sdmapper"; own=1 ;;
            "rom turbo") com="build/m6-sdmapper.rom"; upper=M6 ;;
            "rom turbo-liar") com="build/m6-sdmapper.rom"; upper=M6; product="rom turbo"; liar=1 ;;
            "rom turbo "*) com="build/${product#rom turbo }.rom"; upper=M6; product="rom turbo"; own=1 ;;
            "rom fatacc") com="build/m6-sdmapper.rom"; upper=M6 ;;
            "rom fatacc "*) com="build/${product#rom fatacc }.rom"; upper=M6; product="rom fatacc"; own=1 ;;
            "rom "*) com="build/${product#rom }.rom"; upper=M6; product=rom; own=1 ;;
            *) echo "run-test: $name: the product marker says '$product'; empty, nextor.sys, nextor.sys chain, rom, rom legacy, rom <name>, rom ascii16, rom ascii16 <name>, rom sdmapper, rom sdmapper legacy, rom sdmapper <name>, rom turbo, rom turbo-liar, rom turbo <name>, rom fatacc or rom fatacc <name>" >&2; exit 2 ;;
        esac
        bin=1
        [ -n "$own" ] && bin=""
    else
        com="build/$name.com"
        upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
        bin=""
    fi
    [ -f "$com" ] || { echo "run-test: $com not built; run make first" >&2; exit 2; }
    # The cartridge: the Nextor kernel ROM, or a kernel ROM m6 builds, which
    # the extension finds in the ROM pool beside the Nextor one — copied
    # there now, so the emulator sees this build's.
    ext=m6-sunriseide-nextor
    if [ "$product" = rom ]; then
        cp "$com" tools/openmsx/systemroms/m6-sunriseide.rom
        ext=m6-sunriseide-m6
    elif [ "$product" = "rom ascii16" ]; then
        cp "$com" tools/openmsx/systemroms/m6-ascii16-test.rom
        ext=m6-ascii16-m6
    elif [ "$product" = "rom sdmapper" ]; then
        cp "$com" tools/openmsx/systemroms/m6-sdmapper.rom
        ext=m6-sdmapper-m6
    elif [ "$product" = "rom turbo" ]; then
        cp "$com" tools/openmsx/systemroms/m6-sdmapper.rom
        ext=m6-sdmapper-m6-turbo
        [ -n "$liar" ] && ext=m6-sdmapper-m6-turbo-liar
    elif [ "$product" = "rom fatacc" ]; then
        cp "$com" tools/openmsx/systemroms/m6-sdmapper.rom
        ext=m6-sdmapper-m6-fatacc
    fi
    if [ -n "$liar" ] && [ -n "$slave" ]; then
        echo "run-test: $name: rom turbo-liar takes one card; the disk marker names two" >&2; exit 2
    fi
    [ -n "$slave" ] && ext=$ext-2
    # A product test that boots an SD Mapper ROM names its cartridge as
    # the ROM form does, whatever form it runs as.
    M6_CART=$cart
    case $product in
        "rom sdmapper") M6_CART=sdmapper ;;
        "rom turbo") M6_CART=turbo ;;
        "rom fatacc") M6_CART=fatacc ;;
    esac
    export M6_FORM=$form M6_CART
}

forms=com
[ -f "tests/$name/rom" ] && forms="com rom"

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
# The file is read as text whatever it holds: a screen dumped on a failure
# may carry NULs, and grep would otherwise print one line saying so in
# place of the screen.
openmsx_run() {
    status=0
    "$OPENMSX" -machine "$machine" -setting tools/openmsx/settings.xml \
        -command "set renderer none" "$@" 2> "build/$tag.$machine.err" || status=$?
    grep -a -v \
        -e '^ALSA lib seq_hw\.c:[0-9]*:(snd_seq_hw_open) open /dev/snd/seq failed: ' \
        -e '^error: Could not open sequencer: ' \
        "build/$tag.$machine.err" >&2 || :
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
    ci_vol="build/$tag.$machine.$run.vol"
    dd if="$1" of="$ci_vol" bs=512 skip="$2" count="$3" 2> /dev/null
    # A Nextor boot sector carries no extended signature (29h), and where
    # dosfstools then looks for a volume label it finds nothing: its checker
    # calls every volume an MSX formatter made invalid and exits non-zero
    # for it, before saying anything about the filesystem. Nothing in the
    # system writes a boot sector, so the signature and the name a volume
    # without a label is meant to carry are filled in the carved-out copy —
    # a scratch file, thrown away below — and both checkers then judge the
    # same thing. The BSD one ignores labels and reads the copy exactly as
    # it reads the original.
    printf '\051' | dd of="$ci_vol" bs=1 seek=38 count=1 conv=notrunc 2> /dev/null
    printf 'NO NAME    ' | dd of="$ci_vol" bs=1 seek=43 count=11 conv=notrunc 2> /dev/null
    if ! "$FSCK" -n "$ci_vol" > "$ci_vol.log" 2>&1; then
        echo "run-test: $name: $FSCK finds errors on $(basename "$1") sector $2:" >&2
        cat "$ci_vol.log" >&2
        exit 1
    fi
    # The checker's own step titles name orphans and truncation; what is
    # matched here is a finding, not a title.
    if grep -q -i -E 'differ|lost|found orphan|orphaned|shared|truncating|is bad|wrong|corrupt|reclaim|unused' "$ci_vol.log" > /dev/null; then
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
# The argument lines, read with their line numbers so an empty line counts.
if [ -f "tests/$name/args" ]; then
    runs=$(grep -c '' "tests/$name/args")
else
    runs=1
fi

for form in $forms; do
# The form's runs, as cartridge:machine — the com form on the test's
# machines, the rom form on its marker's lines.
form_runs=""
if [ "$form" = rom ]; then
    while read -r w1 w2; do
        case $w1 in
            "") ;;
            sdmapper) form_runs="$form_runs sdmapper:${w2:-m6-msx2-128k}" ;;
            turbo) form_runs="$form_runs turbo:${w2:-m6-msx2-128k}" ;;
            fatacc) form_runs="$form_runs fatacc:${w2:-m6-msx2-128k}" ;;
            *) form_runs="$form_runs sunrise:$w1" ;;
        esac
    done < "tests/$name/rom"
    [ -n "$form_runs" ] || form_runs=sunrise:m6-msx2-128k
else
    for machine in $machines; do form_runs="$form_runs sunrise:$machine"; done
fi
for form_run in $form_runs; do
    machine=${form_run#*:}
    set_form "$form" "${form_run%%:*}"
    run=0
    while [ "$run" -lt "$runs" ]; do
        run=$((run + 1))
        args=""
        [ -f "tests/$name/args" ] && args=$(sed -n "${run}p" "tests/$name/args")
        formtag=""
        [ "$forms" != com ] && formtag="form $form "
        [ "$cart" = sdmapper ] && formtag="form $form on sdmapper "
        [ "$cart" = turbo ] && formtag="form $form on turbo "
        [ "$cart" = fatacc ] && formtag="form $form on fatacc "
        echo "  ${formtag}machine $machine run $run${args:+ ($args)}"
        rm -rf "$staging" && mkdir -p "$staging"
        case $product in
            "nextor.sys")
                cp "$com" "$staging/NEXTOR.SYS" ;;
            "nextor.sys chain")
                cp "$com" "$staging/NEXTOR.SYS"
                cp .tools/nextor/NEXTOR.SYS "$staging/MSXDOS2.SYS"
                cp .tools/nextor/COMMAND2.COM "$staging/" ;;
            "rom"|"rom ascii16"|"rom sdmapper"|"rom turbo"|"rom fatacc")
                ;;                      # nothing of a system's on the disk
            *)
                cp .tools/nextor/NEXTOR.SYS .tools/nextor/COMMAND2.COM "$staging/"
                cp "$com" "$staging/$upper.COM"
                printf '%s%s\r\n' "$upper" "${args:+ $args}" > "$staging/AUTOEXEC.BAT" ;;
        esac
        if [ -n "$bin" ]; then
            mkdir -p "$staging/bin"
            for b in build/bin/*; do
                case $b in *.lst) ;; *) cp "$b" "$staging/bin/" ;; esac
            done
        fi
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
        export M6_IMAGE="$ROOT/build/$tag.$machine.$run.dsk" M6_STAGING="$ROOT/$staging"
        export M6_EXPORT="$ROOT/build/$tag.$machine.$run.export"
        export M6_MASTER="$master" M6_SLAVE="$slave"
        export M6_SLAVE_IMAGE="$ROOT/build/$tag.$machine.$run.slave.dsk"
        # openMSX's command line takes -hda alone; the slave's image — the
        # SD Mapper's second card — goes in through the hdb command, which
        # runs before the machine boots.
        slave_cmd="set renderer none"
        [ -n "$slave" ] && slave_cmd="hdb $M6_SLAVE_IMAGE"
        # The ASCII16 test ROM's cartridge has no disk: nothing is built or
        # attached, and the test reads the kernel stopping for want of one.
        disk=1
        [ "$product" = "rom ascii16" ] && disk=""
        if [ -n "$disk" ]; then
            M6_STEP=create openmsx_run -script tools/mkdisk.tcl
            M6_STEP=import openmsx_run -ext "$ext" -hda "$M6_IMAGE" -command "$slave_cmd" \
                -script tools/mkdisk.tcl
        fi
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

        # A test that ships lfn-files/ wants that tree on the first
        # volume under LFN/, with the long names the tree's entries carry:
        # the emulator's importer cuts a long name to 8.3, so mtools
        # writes them, with the image closed, before the boot. The
        # partition's offset is the MBR's first entry, or 0 on an image
        # with no table; MTOOLS_SKIP_CHECK because a Nextor boot sector
        # carries no geometry.
        if [ -d "tests/$name/lfn-files" ]; then
            command -v mcopy > /dev/null 2>&1 ||
                { echo "run-test: $name: no mcopy (mtools) on this host" >&2; exit 2; }
            lf_off=0
            if [ "$(byte "$M6_IMAGE" 510)" = 85 ] && [ "$(byte "$M6_IMAGE" 450)" != 0 ]; then
                lf_off=$(( $(le32 "$M6_IMAGE" 454) * 512 ))
            fi
            MTOOLS_SKIP_CHECK=1 mmd -i "$M6_IMAGE@@$lf_off" ::/LFN
            for f in "tests/$name/lfn-files"/* "tests/$name/lfn-files"/.[!.]*; do
                [ -e "$f" ] || continue
                MTOOLS_SKIP_CHECK=1 mcopy -s -i "$M6_IMAGE@@$lf_off" "$f" ::/LFN/
            done
        fi

        # A test that ships patch.tcl wants something on the image no
        # importer writes — an attribute bit. It runs with the image
        # closed, between the import and the boot.
        if [ -f "tests/$name/patch.tcl" ]; then
            openmsx_run -script "tests/$name/patch.tcl"
        fi

        # A test that ships readonly: that image unwritable for the boot
        # (above), and writable again after it, whatever the verdict.
        ro_img=""
        if [ -f "tests/$name/readonly" ]; then
            case $(cat "tests/$name/readonly") in
                master) ro_img=$M6_IMAGE ;;
                slave)
                    [ -n "$slave" ] || { echo "run-test: $name: readonly names the slave, and disk has none" >&2; exit 2; }
                    ro_img=$M6_SLAVE_IMAGE ;;
                *) echo "run-test: $name: readonly says '$(cat "tests/$name/readonly")', not master or slave" >&2; exit 2 ;;
            esac
            chmod a-w "$ro_img"
        fi
        if [ -n "$disk" ]; then
            M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
                openmsx_run -ext "$ext" -ext debugdevice -hda "$M6_IMAGE" -command "$slave_cmd" \
                    -script tools/harness.tcl || { [ -z "$ro_img" ] || chmod u+w "$ro_img"; exit 1; }
            [ -z "$ro_img" ] || chmod u+w "$ro_img"
        else
            M6_TEST="$name" M6_TEST_DIR="$ROOT/tests/$name" \
                openmsx_run -ext "$ext" -ext debugdevice -command "$slave_cmd" \
                    -script tools/harness.tcl
        fi

        # A test that ships check.sh reads its images from outside the
        # machine, with the emulator gone: mtools listing the names the
        # kernel wrote, for one. M6_IMAGE and M6_SLAVE_IMAGE name them.
        if [ -x "tests/$name/check.sh" ]; then
            "tests/$name/check.sh"
        fi

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
done
