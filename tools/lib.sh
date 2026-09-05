# Shared helpers for the fetch scripts under tools/. Source it; it sets ROOT
# (the repository) and TOOLS (.tools, where fetched tools land) and defines
# fetch and verify. POSIX sh; needs curl and shasum.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS="$ROOT/.tools"

# fetch <url> <sha1|sha256> <checksum> <target>
# Downloads once, verifies every time. A mismatch removes the file and fails,
# so nothing half-downloaded or tampered with survives a run.
fetch() {
    if [ ! -f "$4" ]; then
        mkdir -p "$(dirname "$4")"
        echo "fetch: downloading $(basename "$4")" >&2
        curl -fsSL -o "$4.part" "$1" && mv "$4.part" "$4"
    fi
    verify "$2" "$3" "$4"
}

# verify <sha1|sha256> <checksum> <file>
verify() {
    case $1 in
        sha1) bits=1 ;;
        sha256) bits=256 ;;
        *) echo "verify: unknown algorithm $1" >&2; exit 2 ;;
    esac
    actual=$(shasum -a "$bits" "$3" | cut -d' ' -f1)
    if [ "$actual" != "$2" ]; then
        echo "fetch: $1 mismatch for $3" >&2
        echo "  expected $2" >&2
        echo "  actual   $actual" >&2
        rm -f "$3"
        exit 2
    fi
}
