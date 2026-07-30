#!/bin/sh
#
# One entry point for building Tengine distro packages.
#
# Native build (runs on the current host, needs its packaging toolchain):
#
#     packages/build/build.sh rpm            # RHEL / SLES family
#     packages/build/build.sh deb            # Debian / Ubuntu
#     packages/build/build.sh apk            # Alpine
#     packages/build/build.sh auto           # pick by /etc/os-release
#
# Containerised build (needs docker or podman, nothing else):
#
#     packages/build/build.sh docker el9
#     packages/build/build.sh docker all     # every target listed below
#
# Container targets: el7 el8 el9 el10 fedora anolis8 anolis23 openeuler2203
#                    openeuler2403 sles15 debian11 debian12 ubuntu2204
#                    ubuntu2404 alpine
#
# Options:
#     --outdir DIR      artifact directory                  [./dist]
#     --dist .el7u2     RPM dist tag override               [rpm default]
#     --timestamp TS    release timestamp                   [now]
#     --with FEATURE    zstd | lua | geoip (repeatable)     [none]
#     --platform ARCH   docker --platform, e.g. linux/arm64
#     --keep            keep intermediate build trees
#
# Produced artifacts land in --outdir, e.g.
#     tengine-3.2.0-20260604232239.el7u2.x86_64.rpm
#     tengine_3.2.0-20260604232239_amd64.deb
#     tengine-3.2.0_p20260604232239-r0.apk
#
# Written in POSIX sh on purpose: it re-executes itself inside bare distro
# images where /bin/sh may be dash or busybox ash.
#

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_ROOT=$(cd "$SELF_DIR/../.." && pwd)

OUTDIR="$SRC_ROOT/dist"
DIST_TAG=""
BUILD_TS=""
FEATURES=""
PLATFORM=""
KEEP_BUILDDIR=no
TARBALL=""

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

usage() {
    sed -n '3,/^# Written in POSIX/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//' -e '$d'
    exit "${1:-0}"
}

ALL_TARGETS="el7 el8 el9 el10 anolis8 anolis23 openeuler2203 openeuler2403 sles15 debian11 debian12 ubuntu2204 ubuntu2404 alpine"

# Container targets: alias -> "image|family".  family drives both the
# bootstrap commands and which native builder runs inside.
docker_image() {
    case "$1" in
        el7)        echo "centos:7|rpm" ;;
        el8)        echo "rockylinux:8|rpm" ;;
        el9)        echo "rockylinux:9|rpm" ;;
        el10)       echo "almalinux:10|rpm" ;;
        fedora)     echo "fedora:latest|rpm" ;;
        anolis8)    echo "openanolis/anolisos:8.8|rpm" ;;
        anolis23)   echo "openanolis/anolisos:23|rpm" ;;
        openeuler2203) echo "openeuler/openeuler:22.03-lts-sp4|rpm" ;;
        openeuler2403) echo "openeuler/openeuler:24.03-lts|rpm" ;;
        sles15)     echo "registry.suse.com/bci/bci-base:15.6|sles" ;;
        debian11)   echo "debian:11|deb" ;;
        debian12)   echo "debian:12|deb" ;;
        ubuntu2204) echo "ubuntu:22.04|deb" ;;
        ubuntu2404) echo "ubuntu:24.04|deb" ;;
        alpine)     echo "alpine:3.20|apk" ;;
        *)          return 1 ;;
    esac
}

# ---------------------------------------------------------------- arg parsing

[ $# -gt 0 ] || usage 1
ACTION=$1
shift

DOCKER_TARGET=""
if [ "$ACTION" = docker ]; then
    [ $# -gt 0 ] || die "docker requires a target (or 'all'); see --help"
    DOCKER_TARGET=$1
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --outdir)    OUTDIR=$2; shift 2 ;;
        --dist)      DIST_TAG=$2; shift 2 ;;
        --timestamp) BUILD_TS=$2; shift 2 ;;
        --with)      FEATURES="$FEATURES $2"; shift 2 ;;
        --platform)  PLATFORM=$2; shift 2 ;;
        --keep)      KEEP_BUILDDIR=yes; shift ;;
        -h|--help)   usage 0 ;;
        *)           die "unknown option: $1" ;;
    esac
done

TENGINE_VERSION=$(sed -n 's/^#define TENGINE_VERSION *"\(.*\)"/\1/p' \
    "$SRC_ROOT/src/core/nginx.h")
[ -n "$TENGINE_VERSION" ] || die "cannot parse TENGINE_VERSION from src/core/nginx.h"

if [ -z "$BUILD_TS" ]; then
    BUILD_TS=$(date +%Y%m%d%H%M%S)
fi

# --------------------------------------------------------------- source stage

# Builds <outdir>/tengine-<ver>.tar.gz from the working tree.  Tracked files
# plus untracked-but-not-ignored ones go in, so a package can be cut from
# uncommitted work while build products (objs/, dist/) stay out.
make_tarball() {
    stage="$OUTDIR/.stage"
    top="tengine-$TENGINE_VERSION"
    TARBALL="$OUTDIR/$top.tar.gz"

    rm -rf "$stage"
    mkdir -p "$stage/$top"

    info "staging source tree -> $TARBALL"
    if git -C "$SRC_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        ( cd "$SRC_ROOT" && git ls-files -co --exclude-standard -z ) \
            | ( cd "$SRC_ROOT" && tar -cf - --null -T - ) \
            | tar -xf - -C "$stage/$top"
    else
        ( cd "$SRC_ROOT" && tar -cf - \
            --exclude=./dist --exclude=./objs --exclude='./objs-*' \
            --exclude=./.git . ) | tar -xf - -C "$stage/$top"
    fi

    tar -czf "$TARBALL" -C "$stage" "$top"
    rm -rf "$stage"
}

# ------------------------------------------------------------------ rpm build

build_rpm() {
    command -v rpmbuild >/dev/null || die "rpmbuild not found (install rpm-build)"
    make_tarball

    rpmtop="$OUTDIR/rpmbuild"
    rm -rf "$rpmtop"
    mkdir -p "$rpmtop/BUILD" "$rpmtop/BUILDROOT" "$rpmtop/RPMS" \
             "$rpmtop/SRPMS" "$rpmtop/SOURCES" "$rpmtop/SPECS"
    cp "$TARBALL" "$rpmtop/SOURCES/"
    cp "$SELF_DIR/rpm/tengine.spec" "$rpmtop/SPECS/"

    set -- --define "_topdir $rpmtop" \
           --define "tengine_version $TENGINE_VERSION" \
           --define "build_ts $BUILD_TS"
    if [ -n "$DIST_TAG" ]; then
        set -- "$@" --define "dist $DIST_TAG"
    fi
    for f in $FEATURES; do
        set -- "$@" --with "$f"
    done

    info "rpmbuild tengine-$TENGINE_VERSION-${BUILD_TS}${DIST_TAG}"
    rpmbuild -ba "$@" "$rpmtop/SPECS/tengine.spec"

    find "$rpmtop/RPMS" "$rpmtop/SRPMS" -name '*.rpm' -exec cp {} "$OUTDIR/" \;
    [ "$KEEP_BUILDDIR" = yes ] || rm -rf "$rpmtop"
    info "artifacts:"
    ls -1 "$OUTDIR"/*.rpm
}

# ------------------------------------------------------------------ deb build

build_deb() {
    command -v dpkg-buildpackage >/dev/null || \
        die "dpkg-buildpackage not found (install build-essential debhelper)"
    make_tarball

    work="$OUTDIR/debbuild"
    debtop="$work/tengine-$TENGINE_VERSION"
    debversion="$TENGINE_VERSION-$BUILD_TS"

    rm -rf "$work"
    mkdir -p "$work"
    tar -xzf "$TARBALL" -C "$work"

    cp -R "$SELF_DIR/deb/debian" "$debtop/debian"
    cp "$SELF_DIR/conf/tengine.service"   "$debtop/debian/tengine.service"
    cp "$SELF_DIR/conf/tengine.logrotate" "$debtop/debian/tengine.logrotate"

    suite=unstable
    if [ -r /etc/os-release ]; then
        suite=$(. /etc/os-release; echo "${VERSION_CODENAME:-unstable}")
    fi

    sed -e "s|@VERSION@|$debversion|" \
        -e "s|@UPSTREAM_VERSION@|$TENGINE_VERSION|" \
        -e "s|@SUITE@|$suite|" \
        -e "s|@BUILD_DATE@|$(date +%Y-%m-%d)|" \
        -e "s|@DATE_RFC2822@|$(date -R 2>/dev/null || date)|" \
        "$SELF_DIR/deb/debian/changelog.in" > "$debtop/debian/changelog"
    rm -f "$debtop/debian/changelog.in"
    chmod +x "$debtop/debian/rules"

    info "dpkg-buildpackage tengine_$debversion"
    ( cd "$debtop" && dpkg-buildpackage -b -uc -us )

    find "$work" -maxdepth 1 -name '*.deb' -exec cp {} "$OUTDIR/" \;
    [ "$KEEP_BUILDDIR" = yes ] || rm -rf "$work"
    info "artifacts:"
    ls -1 "$OUTDIR"/*.deb
}

# ------------------------------------------------------------------ apk build

build_apk() {
    command -v abuild >/dev/null || die "abuild not found (apk add alpine-sdk)"
    make_tarball

    work="$OUTDIR/apkbuild"
    rm -rf "$work"
    mkdir -p "$work"

    cp "$SELF_DIR/apk/APKBUILD" "$SELF_DIR/apk/tengine.pre-install" "$work/"
    cp "$SELF_DIR/conf/tengine.openrc" "$SELF_DIR/conf/tengine.logrotate" \
       "$SELF_DIR/conf/tengine.conf" "$work/"
    cp "$SELF_DIR/conf/conf.d/default.conf" "$work/"
    cp "$TARBALL" "$work/"

    # pkgver carries the build timestamp as an apk post-release suffix so
    # repeated builds of one upstream version stay distinguishable.
    sed -e "s|^_upstream_ver=.*|_upstream_ver=$TENGINE_VERSION|" \
        -e "s|^pkgver=.*|pkgver=${TENGINE_VERSION}_p${BUILD_TS}|" \
        "$work/APKBUILD" > "$work/APKBUILD.new"
    mv "$work/APKBUILD.new" "$work/APKBUILD"

    [ -f "$HOME/.abuild/abuild.conf" ] || abuild-keygen -a -i -n
    REPODEST="$work/repo"
    export REPODEST

    info "abuild tengine-${TENGINE_VERSION}_p${BUILD_TS}"
    ( cd "$work" && abuild checksum && abuild -F -r )

    find "$work/repo" -name '*.apk' -exec cp {} "$OUTDIR/" \;
    [ "$KEEP_BUILDDIR" = yes ] || rm -rf "$work"
    info "artifacts:"
    ls -1 "$OUTDIR"/*.apk
}

# ------------------------------------------------------------ native dispatch

detect_family() {
    [ -r /etc/os-release ] || die "cannot detect distro: /etc/os-release missing"
    os_id=$(. /etc/os-release; echo "${ID:-}")
    os_like=$(. /etc/os-release; echo "${ID_LIKE:-}")
    case "$os_id $os_like" in
        *alpine*)              echo apk ;;
        *debian*|*ubuntu*)     echo deb ;;
        *suse*|*sles*)         echo rpm ;;
        *rhel*|*fedora*|*centos*|*anolis*|*alinux*) echo rpm ;;
        *) die "unsupported distro '$os_id'; pass rpm|deb|apk explicitly" ;;
    esac
}

# ------------------------------------------------------------ docker dispatch

# Commands that turn a bare distro image into a working build host.
bootstrap_cmd() {
    case "$1" in
        rpm)
            cat <<'EOS'
if command -v dnf >/dev/null 2>&1; then
    if dnf -q list pcre2-devel >/dev/null 2>&1; then _pcre=pcre2-devel; else _pcre=pcre-devel; fi
    dnf -y install rpm-build gcc make tar findutils diffutils \
        openssl-devel zlib-devel systemd "$_pcre"
else
    # CentOS 7 is EOL; its mirrors moved to vault.centos.org
    sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
           -e 's|^#*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' \
           /etc/yum.repos.d/CentOS-*.repo
    yum -y install rpm-build gcc make tar findutils diffutils \
        openssl-devel zlib-devel pcre-devel systemd
fi
EOS
            ;;
        sles)
            echo 'zypper --non-interactive --no-gpg-checks install rpm-build gcc make tar findutils libopenssl-devel zlib-devel pcre2-devel systemd-rpm-macros'
            ;;
        deb)
            echo 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y --no-install-recommends build-essential debhelper libssl-dev zlib1g-dev libpcre2-dev'
            ;;
        apk)
            echo 'apk add --no-cache alpine-sdk linux-headers openssl-dev pcre2-dev zlib-dev'
            ;;
    esac
}

run_docker_target() {
    target=$1
    spec=$(docker_image "$target") || die "unknown docker target: $target"
    image=${spec%|*}
    family=${spec#*|}
    if [ "$family" = sles ]; then
        native_builder=rpm
    else
        native_builder=$family
    fi

    engine=$(command -v docker || command -v podman) || \
        die "neither docker nor podman found"

    inner="--outdir /out --timestamp $BUILD_TS"
    if [ -n "$DIST_TAG" ]; then
        inner="$inner --dist $DIST_TAG"
    fi
    for f in $FEATURES; do
        inner="$inner --with $f"
    done

    set -- run --rm
    if [ -n "$PLATFORM" ]; then
        set -- "$@" --platform "$PLATFORM"
    fi
    set -- "$@" -v "$SRC_ROOT:/src:ro" -v "$OUTDIR:/out" -w / "$image"

    info "[$target] building in $image"
    "$engine" "$@" sh -euc "
        $(bootstrap_cmd "$family")
        mkdir -p /work && cp -a /src /work/tengine
        cd /work/tengine
        sh packages/build/build.sh $native_builder $inner
    "
}

# ----------------------------------------------------------------------- main

mkdir -p "$OUTDIR"

case "$ACTION" in
    rpm)  build_rpm ;;
    deb)  build_deb ;;
    apk)  build_apk ;;
    auto)
        case "$(detect_family)" in
            rpm) build_rpm ;;
            deb) build_deb ;;
            apk) build_apk ;;
        esac
        ;;
    docker)
        if [ "$DOCKER_TARGET" = all ]; then
            failed=""
            for t in $ALL_TARGETS; do
                run_docker_target "$t" || failed="$failed $t"
            done
            [ -z "$failed" ] || die "failed targets:$failed"
        else
            run_docker_target "$DOCKER_TARGET"
        fi
        ;;
    -h|--help) usage 0 ;;
    *) die "unknown action '$ACTION'; expected rpm|deb|apk|auto|docker" ;;
esac
