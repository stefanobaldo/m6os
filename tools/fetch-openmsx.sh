#!/bin/sh
# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# openMSX 21.0 with the FBLabs SD Mapper V2 cartridge and the m6 block
# device, from the project's fork of openMSX
# (github.com/stefanobaldo/m6os-openmsx, branch m6, release m6-21.0.2). On x86_64 Linux the release's portable build is
# fetched into .tools/openmsx/ (bin/ and share/); on macOS on Apple
# silicon its disk image is fetched and the application bundle copied into
# .tools/openmsx/openMSX.app. Anywhere else the fork is built from its tag
# and its build copied into .tools/openmsx/ in one of those two layouts,
# or installed with an openmsx on PATH; the version is checked in every
# case.
. "$(dirname "$0")/lib.sh"

VERSION=21.0-m6.2
TAG=m6-21.0.2
BASE="https://github.com/stefanobaldo/m6os-openmsx/releases/download/$TAG"
LINUX_SHA256=51078c26602f98b8ead45f0f7914b8f67739a5de01abc09a51f542739b14cfec
MAC_SHA256=71efeecdedf5417d62b2c7991d4e01df6f9e3fb1283faa74284ad7db5440df08
BIN="$TOOLS/openmsx/bin/openmsx"
APP="$TOOLS/openmsx/openMSX.app"

# version_of <openmsx binary>: the first line of --version is "openMSX <version>".
version_of() {
    "$1" --version 2>/dev/null | sed -n '1s/^openMSX \([0-9][0-9.a-z-]*\).*/\1/p'
}

os=$(uname -s)
arch=$(uname -m)
if [ "$os" = Linux ] && [ "$arch" = x86_64 ]; then
    if [ -x "$BIN" ] && [ "$(version_of "$BIN")" = "$VERSION" ]; then
        echo "fetch: openMSX $VERSION already in .tools/openmsx" >&2
        exit 0
    fi
    zip="openmsx-$VERSION-linux-x86_64-bin.zip"
    fetch "$BASE/$zip" sha256 "$LINUX_SHA256" "$TOOLS/src/$zip"
    rm -rf "$TOOLS/openmsx"
    mkdir -p "$TOOLS/openmsx"
    unzip -q "$TOOLS/src/$zip" -d "$TOOLS/openmsx"
    got=$(version_of "$BIN")
    if [ "$got" != "$VERSION" ]; then
        echo "fetch: unpacked openMSX reports '$got', expected $VERSION" >&2
        exit 2
    fi
    echo "fetch: openMSX $VERSION unpacked into .tools/openmsx" >&2
elif [ "$os" = Darwin ] && [ "$arch" = arm64 ]; then
    if [ -x "$APP/Contents/MacOS/openmsx" ] && [ "$(version_of "$APP/Contents/MacOS/openmsx")" = "$VERSION" ]; then
        echo "fetch: openMSX $VERSION already in .tools/openmsx/openMSX.app" >&2
        exit 0
    fi
    dmg="openmsx-$VERSION-mac-aarch64-bin.dmg"
    fetch "$BASE/$dmg" sha256 "$MAC_SHA256" "$TOOLS/src/$dmg"
    rm -rf "$TOOLS/openmsx"
    mkdir -p "$TOOLS/openmsx"
    # The image is detached and the mount point removed on every way out,
    # an interrupt included.
    mnt=$(mktemp -d "${TMPDIR:-/tmp}/openmsx-dmg.XXXXXX")
    attached=
    trap '[ -z "$attached" ] || hdiutil detach -quiet "$mnt" || true; rmdir "$mnt" 2>/dev/null || true' EXIT
    trap 'exit 130' INT TERM HUP
    hdiutil attach -nobrowse -quiet -readonly -mountpoint "$mnt" "$TOOLS/src/$dmg"
    attached=1
    cp -R "$mnt/openMSX.app" "$APP"
    hdiutil detach -quiet "$mnt"
    attached=
    rmdir "$mnt"
    trap - EXIT INT TERM HUP
    got=$(version_of "$APP/Contents/MacOS/openmsx")
    if [ "$got" != "$VERSION" ]; then
        echo "fetch: the application in the disk image reports '$got', expected $VERSION" >&2
        exit 2
    fi
    echo "fetch: openMSX $VERSION copied into .tools/openmsx/openMSX.app" >&2
else
    for b in "$BIN" "$APP/Contents/MacOS/openmsx"; do
        if [ -x "$b" ] && [ "$(version_of "$b")" = "$VERSION" ]; then
            echo "fetch: using openMSX $VERSION built into ${b#"$ROOT"/}" >&2
            exit 0
        fi
    done
    if [ "$os" = Darwin ]; then
        built="derived/*/bindist/openMSX.app \"$TOOLS/openmsx/\""
    else
        built="derived/*/bindist/install/. \"$TOOLS/openmsx/\""
    fi
    if ! command -v openmsx >/dev/null 2>&1; then
        echo "fetch: no openMSX build to fetch for $os/$arch; build the fork's tag into .tools/openmsx:" >&2
        echo "  git clone --depth 1 --branch $TAG https://github.com/stefanobaldo/m6os-openmsx.git && cd m6os-openmsx && make staticbindist" >&2
        echo "  mkdir -p \"$TOOLS/openmsx\" && cp -R $built" >&2
        exit 2
    fi
    got=$(version_of openmsx)
    if [ "$got" != "$VERSION" ]; then
        echo "fetch: openmsx on PATH is version '$got', expected $VERSION (the fork's tag $TAG)" >&2
        exit 2
    fi
    echo "fetch: using openMSX $VERSION from PATH ($(command -v openmsx))" >&2
fi
