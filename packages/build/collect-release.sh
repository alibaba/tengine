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
#     --debugdir DIR directory for debug symbols         [<outdir>-debug]
#
# Debug symbols go to their own directory with their own checksum file, rather
# than mixed in with the runtime packages. They are the larger half of every
# build and nobody installing Tengine needs them, so keeping the two apart
# makes the release listing readable -- and it is the grouping a package
# repository would want later, where debug symbols conventionally live in a
# separate repo. The directory is a sibling rather than a subdirectory so that
# a plain "<outdir>/*" glob still expands to files only.
#
# Three artifact naming quirks have to be handled, or files would silently
# overwrite each other once the per-job directories are merged -- or, in the
# deb case, arrive under a name the checksum file does not know:
#
#   * apk file names carry neither the architecture nor anything identifying the
#     Alpine release they were built on, so every alpine target and architecture
#     would produce the same name. Both are appended here, which is what lets the
#     release ship one apk per Alpine version.
#   * deb versions carry the distro codename after a tilde (3.2.0-<ts>~bookworm),
#     but GitHub rewrites "~" to "." in release asset names. The tilde spelling
#     is therefore renamed away here, before the checksums are taken -- see the
#     comment at the rename itself for why the package's own version is left
#     alone.
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
DEBUGDIR=""

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --indir)    INDIR=$2; shift 2 ;;
        --outdir)   OUTDIR=$2; shift 2 ;;
        --debugdir) DEBUGDIR=$2; shift 2 ;;
        -h|--help) sed -n '3,/^$/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -d "$INDIR" ] || die "$INDIR does not exist"
[ -n "$DEBUGDIR" ] || DEBUGDIR="$OUTDIR-debug"

if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
    sums_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
    sums_cmd="shasum -a 256"
else
    die "no sha256 tool found (need sha256sum or shasum)"
fi

mkdir -p "$OUTDIR" "$DEBUGDIR"

# Debug symbol packages, by the name each packaging format gives them:
# rpm splits out -debuginfo and -debugsource, deb produces tengine-dbgsym
# (.deb on Debian, .ddeb on Ubuntu), Alpine produces tengine-dbg.
is_debug() {
    case "$1" in
        *-debuginfo-*.rpm|*-debugsource-*.rpm) return 0 ;;
        tengine-dbgsym_*.deb|tengine-dbgsym_*.ddeb) return 0 ;;
        tengine-dbg-*.apk) return 0 ;;
        *) return 1 ;;
    esac
}

copied=0
debug_copied=0
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
            # GitHub serves a release asset under a name with "~" replaced by
            # ".", so a deb built as ...-<ts>~bookworm_amd64.deb is downloaded
            # as ...-<ts>.bookworm_amd64.deb. Taking the checksums from the
            # original spelling would make "sha256sum -c SHA256SUMS" fail for
            # every deb -- and fail invisibly under --ignore-missing, which
            # skips names it cannot find. Renaming here keeps the checksum file
            # and the download in agreement.
            #
            # Only the file name changes. The version inside the package still
            # carries the tilde, which is what apt compares, and what keeps a
            # codename build sorting below the plain version.
            *.deb|*.ddeb) base=$(printf '%s' "$base" | tr '~' '.') ;;
            *.src.rpm) srcrpm=yes ;;
        esac

        # Decided on the final name, so an apk that was just given its target
        # and architecture is classified the same way as everything else.
        if is_debug "$base"; then
            destdir="$DEBUGDIR"
        else
            destdir="$OUTDIR"
        fi

        dest="$destdir/$base"
        if [ -e "$dest" ]; then
            # A source rpm that is already there came from this target's other
            # architecture and carries the same sources, so drop it without
            # comparing checksums -- they never match.
            if [ "$srcrpm" = yes ] || \
               [ "$(sha256_of "$src")" = "$(sha256_of "$dest")" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            dest="$destdir/$target-$base"
            [ -e "$dest" ] && die "cannot place $src: both $base and $target-$base already exist with different content"
            info "name clash on $base, keeping this one as $target-$base"
            renamed=$((renamed + 1))
        fi

        cp -p "$src" "$dest"
        if [ "$destdir" = "$OUTDIR" ]; then
            copied=$((copied + 1))
        else
            debug_copied=$((debug_copied + 1))
        fi
    done
done

[ "$((copied + debug_copied))" -gt 0 ] || die "no artifacts found under $INDIR"

# One checksum file per group, each covering only its own directory so that
# `sha256sum -c` works after downloading just one of the two.
# $2 is the checksum file name: the two directories are merged into one flat
# asset list at release time, so the debug one cannot also be called SHA256SUMS.
write_sums() {
    dir=$1
    name=$2
    # Feed sha256sum an explicit list: an unmatched glob would otherwise reach
    # it as a literal. A previous run's checksum file is the only non-package
    # entry either directory can hold.
    files=$(cd "$dir" && ls -1 2>/dev/null | grep -v "^$name$" || true)
    [ -n "$files" ] || return 0
    ( cd "$dir" && echo "$files" | xargs $sums_cmd > "$name" )
}

write_sums "$OUTDIR" SHA256SUMS
write_sums "$DEBUGDIR" SHA256SUMS.debug

# An empty debug directory would otherwise reach the release as a stray entry.
rmdir "$DEBUGDIR" 2>/dev/null || true

info "collected $copied packages into $OUTDIR and $debug_copied debug packages into $DEBUGDIR ($skipped duplicates dropped, $renamed renamed)"
ls -lh "$OUTDIR"
if [ -d "$DEBUGDIR" ]; then
    ls -lh "$DEBUGDIR"
fi
