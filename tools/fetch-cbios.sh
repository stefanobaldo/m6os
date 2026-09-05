#!/bin/sh
# The three C-BIOS MSX2 ROMs, from the v0.29-nextor.1 release of
# github.com/stefanobaldo/cbios, into the ROM pool tools/openmsx/systemroms/.
# The sha1s are the ones the machine XML selects the ROMs by.
. "$(dirname "$0")/lib.sh"

RELEASE=v0.29-nextor.1
BASE="https://github.com/stefanobaldo/cbios/releases/download/$RELEASE"
POOL="$ROOT/tools/openmsx/systemroms"

fetch "$BASE/cbios_main_msx2.rom" sha1 708097c2369046b65e6a41f5ca8ede2346fde93f "$POOL/cbios_main_msx2.rom"
fetch "$BASE/cbios_logo_msx2.rom" sha1 d4e5b98ce23573669fb44447582d656e390791c0 "$POOL/cbios_logo_msx2.rom"
fetch "$BASE/cbios_sub.rom"       sha1 2fcb40413e7d373f0f2dbdc815ce18746ddf3684 "$POOL/cbios_sub.rom"
echo "fetch: C-BIOS $RELEASE ROMs ready in tools/openmsx/systemroms" >&2
