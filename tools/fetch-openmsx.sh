#!/bin/sh
# openMSX 21.0. On x86_64 Linux the official portable build is fetched into
# .tools/openmsx/ (bin/ and share/). Anywhere else there is no portable build
# to fetch, so an openmsx on PATH is required and its version checked.
. "$(dirname "$0")/lib.sh"

VERSION=21.0
SHA256=53cc1e9dc3a97b0ff56d1a1572b3ffdbba4fcaee3eb78c4391b9b1443f92284a
URL="https://github.com/openMSX/openMSX/releases/download/RELEASE_21_0/openmsx-$VERSION-linux-x86_64-bin.zip"
BIN="$TOOLS/openmsx/bin/openmsx"

# version_of <openmsx binary>: the first line of --version is "openMSX <version>".
version_of() {
    "$1" --version 2>/dev/null | sed -n '1s/^openMSX \([0-9][0-9.]*\).*/\1/p'
}

if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
    if [ -x "$BIN" ] && [ "$(version_of "$BIN")" = "$VERSION" ]; then
        echo "fetch: openMSX $VERSION already in .tools/openmsx" >&2
        exit 0
    fi
    fetch "$URL" sha256 "$SHA256" "$TOOLS/src/openmsx-$VERSION-linux-x86_64-bin.zip"
    rm -rf "$TOOLS/openmsx"
    mkdir -p "$TOOLS/openmsx"
    unzip -q "$TOOLS/src/openmsx-$VERSION-linux-x86_64-bin.zip" -d "$TOOLS/openmsx"
    got=$(version_of "$BIN")
    if [ "$got" != "$VERSION" ]; then
        echo "fetch: unpacked openMSX reports '$got', expected $VERSION" >&2
        exit 2
    fi
    echo "fetch: openMSX $VERSION unpacked into .tools/openmsx" >&2
else
    if ! command -v openmsx >/dev/null 2>&1; then
        echo "fetch: no portable openMSX build for $(uname -s)/$(uname -m); install openMSX $VERSION and put openmsx on PATH" >&2
        exit 2
    fi
    got=$(version_of openmsx)
    if [ "$got" != "$VERSION" ]; then
        echo "fetch: openmsx on PATH is version '$got', expected $VERSION" >&2
        exit 2
    fi
    echo "fetch: using openMSX $VERSION from PATH ($(command -v openmsx))" >&2
fi
