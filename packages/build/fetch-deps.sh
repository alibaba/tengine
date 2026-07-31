#!/bin/sh
#
# Downloads the third-party sources pinned in deps.env and verifies their
# checksums.  Every packaging recipe and container image build starts here, so
# that all of them compile the exact same Tongsuo / xquic / Lua revisions.
#
#     packages/build/fetch-deps.sh                     # -> ./dist/deps
#     packages/build/fetch-deps.sh --outdir /tmp/deps
#     packages/build/fetch-deps.sh --print-checksums    # after a version bump
#
# Options:
#     --outdir DIR         where tarballs land            [<srcroot>/dist/deps]
#     --only ID[,ID...]    fetch a subset (ids from deps.env)
#     --print-checksums    re-hash what was fetched and print deps.env lines
#                          instead of verifying against them
#
# A tarball that is already present and matches its pinned checksum is left
# alone, so re-running is cheap and works offline once primed.
#

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_ROOT=$(cd "$SELF_DIR/../.." && pwd)

OUTDIR="$SRC_ROOT/dist/deps"
ONLY=""
PRINT_CHECKSUMS=no

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --outdir)          OUTDIR=$2; shift 2 ;;
        --only)            ONLY=$(echo "$2" | tr ',' ' '); shift 2 ;;
        --print-checksums) PRINT_CHECKSUMS=yes; shift ;;
        -h|--help)         sed -n '3,/^$/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
        *)                 die "unknown option: $1" ;;
    esac
done

. "$SELF_DIR/deps.env"

# sha256: coreutils on Linux, BSD shasum on macOS, openssl as a last resort.
if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v openssl >/dev/null 2>&1; then
    sha256_of() { openssl dgst -sha256 "$1" | sed 's/.*= *//'; }
else
    die "no sha256 tool found (need sha256sum, shasum or openssl)"
fi

DOWNLOAD_TRIES=3
DOWNLOAD_DELAY=3

if command -v curl >/dev/null 2>&1; then
    # $3 carries the per-attempt options chosen by download(); it is deliberately
    # unquoted so that an empty value adds no argument at all.
    # shellcheck disable=SC2086
    fetch_to() { curl -fsSL --connect-timeout 20 --retry 2 --retry-delay 2 ${3:-} -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    # wget only speaks HTTP/1.1, so it ignores $3.
    fetch_to() { wget -q --timeout=20 --tries=2 --waitretry=2 -O "$2" "$1"; }
else
    die "neither curl nor wget found"
fi

# Retrying in the shell rather than leaving it to curl: a truncated HTTP/2
# stream exits 18, which --retry does not consider transient, and covering it
# with --retry-all-errors would need curl 7.71 (newer than el7 ships).  Without
# an outer retry a single network hiccup fails a whole packaging run.
#
# A failed attempt can leave a partial file behind, which the caller would then
# hash as if it were complete, so drop it before retrying.
download() {
    _try=1
    while :; do
        # Networks that truncate HTTP/2 streams are usually fine over HTTP/1.1,
        # so retries drop to it.  The first attempt keeps HTTP/2, which is
        # faster where it works.
        if [ "$_try" = 1 ]; then
            _opt=""
        else
            _opt="--http1.1"
        fi
        if fetch_to "$1" "$2" "$_opt"; then
            return 0
        fi
        rm -f "$2"
        if [ "$_try" -ge "$DOWNLOAD_TRIES" ]; then
            return 1
        fi
        warn "download failed, retrying in ${DOWNLOAD_DELAY}s ($_try/$DOWNLOAD_TRIES)"
        _try=$((_try + 1))
        sleep "$DOWNLOAD_DELAY"
    done
}

mkdir -p "$OUTDIR"

ids=${ONLY:-$TENGINE_DEP_IDS}

for id in $ids; do
    eval "spec=\${dep_$id:-}"
    [ -n "$spec" ] || die "unknown dependency id '$id' (not in deps.env)"

    # shellcheck disable=SC2086  # deliberate word splitting of the 4 fields
    set -- $spec
    repo=$1
    tag=$2
    want_sha=$4

    tarball="$OUTDIR/$id-$tag.tar.gz"
    url="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"

    if [ -f "$tarball" ]; then
        got_sha=$(sha256_of "$tarball")
        if [ "$PRINT_CHECKSUMS" = yes ] || [ "$got_sha" = "$want_sha" ]; then
            info "have $id-$tag"
        else
            info "re-downloading $id-$tag (checksum mismatch)"
            rm -f "$tarball"
        fi
    fi

    if [ ! -f "$tarball" ]; then
        info "fetching $repo@$tag"
        download "$url" "$tarball" || die "download failed: $url"
        got_sha=$(sha256_of "$tarball")
    fi

    if [ "$PRINT_CHECKSUMS" = yes ]; then
        printf 'dep_%s="%s %s %s %s"\n' "$id" "$repo" "$tag" "$3" "$got_sha"
    elif [ "$got_sha" != "$want_sha" ]; then
        die "checksum mismatch for $id-$tag
  expected $want_sha
  got      $got_sha
The tag may have been re-cut upstream. Verify the source, then refresh
deps.env with: packages/build/fetch-deps.sh --print-checksums"
    fi
done

[ "$PRINT_CHECKSUMS" = yes ] || info "dependencies verified in $OUTDIR"
