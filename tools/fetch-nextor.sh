#!/bin/sh
# The pinned Nextor files from github.com/Konamiman/Nextor releases: the
# 2.1.4 Sunrise IDE kernel ROM into the ROM pool (the extension XML selects it
# by sha1), and NEXTOR.SYS (last published on v2.1.3) and COMMAND2.COM (from
# tools.zip on v2.1.0) into .tools/nextor/ for the disk image.
. "$(dirname "$0")/lib.sh"

BASE="https://github.com/Konamiman/Nextor/releases/download"
POOL="$ROOT/tools/openmsx/systemroms"
DIR="$TOOLS/nextor"

fetch "$BASE/v2.1.4/Nextor-2.1.4.SunriseIDE.ROM" sha256 \
      4eafcd3a4918da7da98559b2b598d430521d35857f1bf0d2ba6619f8e71c05b2 "$POOL/Nextor-2.1.4.SunriseIDE.ROM"
fetch "$BASE/v2.1.3/NEXTOR.SYS" sha256 \
      3db8c8094bd5d3df4197b2f6606d4e28fb5a2462086f72ce8b6664d12a94bde7 "$DIR/NEXTOR.SYS"
fetch "$BASE/v2.1.0/tools.zip" sha256 \
      5792ff3fe7ab684b8afd405cdd898e25f6efdb84ca1f2cb9ac1428cc848d924e "$DIR/tools.zip"
if [ ! -f "$DIR/COMMAND2.COM" ]; then
    unzip -o -q -j "$DIR/tools.zip" COMMAND2.COM -d "$DIR"
fi
verify sha256 1bb7860631cd6257fefdbd996640bd345d7eab931758e7dc2725cdb02072067c "$DIR/COMMAND2.COM"
echo "fetch: Nextor 2.1.4 kernel ROM, NEXTOR.SYS 2.1.3 and COMMAND2.COM 2.1.0 ready" >&2
