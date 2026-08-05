#!/bin/sh
#
# Prints the container image tags for one flavour, one per line, in the same
# shape the nginx official images publish:
#
#     nginx   1.31.3  1.31  1  latest  1.31.3-trixie  1.31-trixie  1-trixie  trixie
#     tengine 3.2.0   3.2   3  latest  3.2.0-trixie   3.2-trixie   3-trixie  trixie
#
#     .github/scripts/image-tags.sh debian 3.2.0 true
#     .github/scripts/image-tags.sh alpine 3.2.0 true
#
# A fourth argument names an image variant, which is appended to every tag the
# same way nginx suffixes its own variants:
#
#     .github/scripts/image-tags.sh debian 3.2.0 true perl
#         -> 3.2.0-perl 3.2.0-trixie-perl ... perl trixie-perl
#
# Version-pinned tags (3.2.0, 3.2.0-trixie) are always printed. The rolling
# tags -- the minor and major series, "latest" and the bare distro name -- only
# come out when <move-rolling> is true, so a pre-release tag can never become
# what `docker pull tengine` resolves to.
#
# The distro part is read back from the Dockerfiles instead of being repeated
# here, so rebasing an image moves its tags along with it.
#
# Used by .github/workflows/docker.yml.
#

set -eu

[ $# -eq 3 ] || [ $# -eq 4 ] || {
    echo "usage: ${0##*/} <debian|alpine> <version> <move-rolling:true|false> [variant]" >&2
    exit 2
}

FLAVOR=$1
VERSION=$2
MOVE=$3
VARIANT=${4:-}

# Appended to every tag: "" for the default image, "-perl" for the perl one.
sfx=${VARIANT:+-$VARIANT}

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR/../.." && pwd)

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }

# The base image is an ARG default in the Dockerfile; take the first match so a
# later FROM referencing ${BASE_IMAGE} cannot confuse the parse.
base_version() {  # <dockerfile> <image name>
    sed -n "s/^ARG BASE_IMAGE=$2:\([0-9][0-9.]*\).*/\1/p" "$ROOT/$1" | head -n 1
}

case "$FLAVOR" in
    debian)
        release=$(base_version Dockerfile debian)
        [ -n "$release" ] || die "cannot read the debian release from Dockerfile"
        # Debian's own release-to-codename map. Add the next entry when the
        # Dockerfile is rebased; an unknown release is a hard error rather than
        # a silently missing tag.
        case "$release" in
            11) distro=bullseye ;;
            12) distro=bookworm ;;
            13) distro=trixie   ;;
            14) distro=forky    ;;
            *)  die "unknown Debian release '$release' -- add its codename here" ;;
        esac
        # Debian is the default flavour, so it owns the unsuffixed tags.
        flavor_tag=
        ;;
    alpine)
        release=$(base_version Dockerfile.alpine alpine)
        [ -n "$release" ] || die "cannot read the alpine version from Dockerfile.alpine"
        distro="alpine$release"
        flavor_tag=alpine
        ;;
    *)
        die "unknown flavour: $FLAVOR"
        ;;
esac

# Only a plain "3.2.0" can carry rolling tags. A -rc, or the -dev-<sha> version
# a manual run builds, keeps its pinned tags and nothing else -- even if the
# caller asked for the rolling ones.
minor=$(printf '%s' "$VERSION" | sed -n 's/^\([0-9]\{1,\}\.[0-9]\{1,\}\)\.[0-9]\{1,\}$/\1/p')
major=$(printf '%s' "$VERSION" | sed -n 's/^\([0-9]\{1,\}\)\.[0-9]\{1,\}\.[0-9]\{1,\}$/\1/p')
[ -n "$minor" ] || MOVE=false

series=$VERSION
if [ "$MOVE" = true ]; then
    series="$series $minor $major"
fi

# Each series gets both an unsuffixed (or -alpine) tag and a distro-suffixed
# one: 3.2.0 / 3.2.0-trixie, 3.2.0-alpine / 3.2.0-alpine3.24.
for v in $series; do
    echo "$v${flavor_tag:+-$flavor_tag}$sfx"
    echo "$v-$distro$sfx"
done

# The floating aliases: "latest"/"alpine" and the bare distro name. A variant
# replaces "latest" rather than extending it, which is how nginx spells them --
# "perl" and "alpine-perl", never "latest-perl".
if [ "$MOVE" = true ]; then
    alias_tag=$flavor_tag
    [ -n "$VARIANT" ] && alias_tag="${alias_tag:+$alias_tag-}$VARIANT"
    echo "${alias_tag:-latest}"
    echo "$distro$sfx"
fi
