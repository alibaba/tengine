#!/bin/sh
#
# Flattens the per-target build artifacts into one directory fit for a GitHub
# release, and writes SHA256SUMS.
#
#     packages/build/collect-release.sh --indir artifacts --outdir release
#
# Options:
#     --indir DIR    directory of downloaded artifacts   [artifacts]
#                    expects one subdirectory per matrix job, named
#                    tengine-<target>-<arch> (as package.yml uploads them)
#     --outdir DIR   flattened output directory          [release]
#
# Two artifact naming quirks have to be handled, or files would silently
# overwrite each other once the per-job directories are merged:
#
#   * apk file names carry neither the architecture nor anything identifying the
#     Alpine release they were built on, so every alpine target and architecture
#     would produce the same name. Both are appended here, which is what lets the
#     release ship one apk per Alpine version.
#   * every architecture's job produces a .src.rpm of the same sources, but rpm
#     stamps the build platform into the header, so the two are not byte-equal
#     and a checksum comparison cannot dedupe them. One per target is what a
#     release needs, so the second architecture's copy is dropped.
#
# Anything else that collides is kept under a <target>- prefix rather than
# overwritten, and a collision that survives even that is a hard error: a
# release must never quietly ship fewer packages than it built.
#

set -eu

INDIR="artifacts"
OUTDIR="release"

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --indir)  INDIR=$2; shift 2 ;;
        --outdir) OUTDIR=$2; shift 2 ;;
        -h|--help) sed -n '3,/^$/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -d "$INDIR" ] || die "$INDIR does not exist"

if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
    sums_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
    sums_cmd="shasum -a 256"
else
    die "no sha256 tool found (need sha256sum or shasum)"
fi

mkdir -p "$OUTDIR"

copied=0
skipped=0
renamed=0

for jobdir in "$INDIR"/*; do
    [ -d "$jobdir" ] || continue

    jobname=$(basename "$jobdir")
    # tengine-el9-x86_64 -> target "el9", arch "x86_64"
    rest=${jobname#tengine-}
    arch=${rest##*-}
    target=${rest%-*}

    for src in "$jobdir"/*; do
        [ -f "$src" ] || continue
        base=$(basename "$src")

        srcrpm=no
        case "$base" in
            *.apk)     base="${base%.apk}.$target.$arch.apk" ;;
            *.src.rpm) srcrpm=yes ;;
        esac

        dest="$OUTDIR/$base"
        if [ -e "$dest" ]; then
            # A source rpm that is already there came from this target's other
            # architecture and carries the same sources, so drop it without
            # comparing checksums -- they never match.
            if [ "$srcrpm" = yes ] || \
               [ "$(sha256_of "$src")" = "$(sha256_of "$dest")" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            dest="$OUTDIR/$target-$base"
            [ -e "$dest" ] && die "cannot place $src: both $base and $target-$base already exist with different content"
            info "name clash on $base, keeping this one as $target-$base"
            renamed=$((renamed + 1))
        fi

        cp -p "$src" "$dest"
        copied=$((copied + 1))
    done
done

[ "$copied" -gt 0 ] || die "no artifacts found under $INDIR"

( cd "$OUTDIR" && $sums_cmd ./* > SHA256SUMS.tmp 2>/dev/null || true
  # Strip the "./" prefix so `sha256sum -c` works from inside the directory.
  sed -e 's| \./| |' SHA256SUMS.tmp | grep -v ' SHA256SUMS' > SHA256SUMS
  rm -f SHA256SUMS.tmp )

info "collected $copied files into $OUTDIR ($skipped duplicates dropped, $renamed renamed)"
ls -lh "$OUTDIR"
