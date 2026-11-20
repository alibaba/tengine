#!/bin/sh
#
# Holds a `tengine -V` banner against the sources this checkout pins: the
# Tengine and nginx core versions from src/core/nginx.h, and the Tongsuo and
# xquic releases named in packages/build/deps.env.
#
# The banner is read from stdin:
#
#     tengine -V 2>&1 | .github/scripts/check-pinned-versions.sh
#     .github/scripts/check-pinned-versions.sh --srcdir /src < /tmp/banner
#
# Options:
#     --srcdir DIR   tree holding src/core/nginx.h and packages/build/deps.env
#                    [the one this script lives in]
#
# Both verification paths call it: verify-image.sh for the container images and
# the verify job of .github/workflows/package.yml for the rpm, deb and apk. A
# release therefore cannot ship a binary built against anything other than the
# pinned baseline -- a reverted deps.env, a stale builder layer or a package
# assembled from the wrong tree all fail here instead of reaching a user.
#
# The dependency versions are matched through the source directory names that
# configure records verbatim in its argument list:
#
#     --with-openssl=../deps-build/Tongsuo-8.5.0
#     --with-xquic-inc=../deps-build/xquic-1.9.8/include
#
# Those names are field 3 of each deps.env entry, so the check follows a version
# bump with no edit here. It is the last link of a chain that starts at the
# sha256 fetch-deps.sh verifies: a pinned checksum means the tarball content is
# fixed, the tarball's top level directory is that field 3, and build-deps.sh
# points configure at it -- so the name in the banner identifies the exact
# sources the binary was compiled from.
#
# Plain text output on purpose: this runs inside alpine (busybox), debian and
# RHEL-family containers as well as on the runners, so it stays off any escape
# sequence a minimal shell might not emit.
#
# Every mismatch is reported rather than just the first one: a build that drifted
# off the baseline usually drifted on more than one axis, and one CI run should
# say so in full.
#

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR=$(cd "$SELF_DIR/../.." && pwd)

while [ $# -gt 0 ]; do
    case "$1" in
        --srcdir) SRC_DIR=$(cd "$2" && pwd); shift 2 ;;
        -h|--help) sed -n '3,/^$/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
        *) echo "${0##*/}: unknown option: $1" >&2; exit 2 ;;
    esac
done

ok()   { printf '  ok   %s\n' "$*"; }
# A setup problem: nothing meaningful can be checked, so stop here.
die()  { printf '  FAIL %s\n' "$*" >&2; exit 1; }
# A version mismatch: record it, keep going, fail the run at the end.
FAILED=no
bad()  { printf '  FAIL %s\n' "$*" >&2; FAILED=yes; }

banner=$(cat)
[ -n "$banner" ] || die "empty banner on stdin"

nginx_h="$SRC_DIR/src/core/nginx.h"
deps_env="$SRC_DIR/packages/build/deps.env"
[ -f "$nginx_h" ]  || die "no src/core/nginx.h under $SRC_DIR (pass --srcdir)"
[ -f "$deps_env" ] || die "no packages/build/deps.env under $SRC_DIR (pass --srcdir)"

# ---------------------------------------------------------------- core versions

# The banner spells both as "<label> version: <label>/<number>", and both numbers
# come from the tree the binary was compiled from -- not from a release tag, so
# an rc pre-release still reports the plain 3.2.0 of TENGINE_VERSION.
for pair in "Tengine:TENGINE_VERSION" "nginx:NGINX_VERSION"; do
    label=${pair%%:*}
    macro=${pair##*:}
    want=$(sed -n "s/^#define $macro *\"\(.*\)\"\$/\1/p" "$nginx_h")
    [ -n "$want" ] || die "cannot parse $macro out of src/core/nginx.h"
    case $banner in
        *"$label version: $label/$want"*)
            ok "$label $want matches src/core/nginx.h" ;;
        *)
            got=$(printf '%s\n' "$banner" \
                | sed -n "s/^$label version: $label\/\([^ ]*\).*/\1/p" | head -n 1)
            bad "banner reports $label/${got:-<none>} but src/core/nginx.h pins $want" ;;
    esac
done

# ---------------------------------------------------------- pinned dependencies

# Only these two reach the banner. LuaJIT is passed through --with-cc-opt and
# --with-ld-opt, which the recipes assemble per distro, so no stable path of its
# own is recorded.
for dep in tongsuo xquic; do
    spec=$(sed -n "s/^dep_$dep=\"\(.*\)\"\$/\1/p" "$deps_env")
    [ -n "$spec" ] || die "no dep_$dep entry in packages/build/deps.env"

    # shellcheck disable=SC2086  # deliberate word splitting of the four fields
    set -- $spec
    [ $# -ge 3 ] || die "dep_$dep in packages/build/deps.env has fewer than three fields"
    dir=$3

    case $banner in
        *"$dir"*)
            ok "$dep built from the pinned $dir" ;;
        *)
            bad "$dep: the configure arguments never mention $dir, so this binary was
       not built against what packages/build/deps.env pins for dep_$dep" ;;
    esac
done

[ "$FAILED" = no ] || exit 1
