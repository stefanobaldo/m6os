#!/bin/sh
# sjasmplus 1.24.0, built from the pinned source tarball into .tools/sjasmplus/.
# Needs a C++ compiler and make. Idempotent: a built binary reporting the
# pinned version is kept.
. "$(dirname "$0")/lib.sh"

VERSION=1.24.0
SHA256=0b5013f07e8d8505f9e296529655668b6fdf0268625c19e883b0fff484e209f1
URL="https://github.com/z00m128/sjasmplus/releases/download/v$VERSION/sjasmplus-$VERSION-src.tar.xz"
BIN="$TOOLS/sjasmplus/bin/sjasmplus"

if [ -x "$BIN" ] && [ "$("$BIN" --nologo --version 2>&1)" = "$VERSION" ]; then
    echo "fetch: sjasmplus $VERSION already in .tools/sjasmplus" >&2
    exit 0
fi

SRC="$TOOLS/src"
fetch "$URL" sha256 "$SHA256" "$SRC/sjasmplus-$VERSION-src.tar.xz"
rm -rf "$SRC/sjasmplus-$VERSION"
tar xJf "$SRC/sjasmplus-$VERSION-src.tar.xz" -C "$SRC"
jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
make -s -C "$SRC/sjasmplus-$VERSION" -j"$jobs"
mkdir -p "$(dirname "$BIN")"
cp "$SRC/sjasmplus-$VERSION/sjasmplus" "$BIN"
rm -rf "$SRC/sjasmplus-$VERSION"

built=$("$BIN" --nologo --version 2>&1)
if [ "$built" != "$VERSION" ]; then
    echo "fetch: built sjasmplus reports '$built', expected $VERSION" >&2
    exit 2
fi
echo "fetch: sjasmplus $VERSION built into .tools/sjasmplus" >&2
