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
#                    openeuler2403 sles15 sles16 debian11 debian12 debian13
#                    ubuntu2204 ubuntu2404 ubuntu2604 alpine321 alpine322
#                    alpine323 alpine324
#
# Tongsuo (NTLS), xquic (QUIC/HTTP-3) and the Lua stack are part of the default
# feature set. Their sources are pinned in packages/build/deps.env, downloaded
# once into <outdir>/deps by fetch-deps.sh and handed to every recipe as a
# single tengine-deps.tar.gz, so all targets compile identical dependencies.
#
# Options:
#     --outdir DIR      artifact directory                  [./dist]
#     --dist .el7u2     RPM dist tag override               [rpm default]
#     --timestamp TS    release timestamp                   [now]
#     --with FEATURE    zstd | geoip (repeatable)           [none]
#     --without FEATURE tongsuo | xquic | lua (repeatable)  [none]
#     --platform ARCH   docker --platform, e.g. linux/arm64
#     --keep            keep intermediate build trees
#
# Produced artifacts land in --outdir, e.g.
#     tengine-3.2.0-20260604232239.el7u2.x86_64.rpm
#     tengine_3.2.0-20260604232239~bookworm_amd64.deb
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
DISABLED=""
PLATFORM=""
KEEP_BUILDDIR=no
TARBALL=""
DEPS_TARBALL=""

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

usage() {
    sed -n '3,/^# Written in POSIX/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//' -e '$d'
    exit "${1:-0}"
}

ALL_TARGETS="el7 el8 el9 el10 anolis8 anolis23 openeuler2203 openeuler2403 sles15 sles16 debian11 debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604 alpine321 alpine322 alpine323 alpine324"

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
        sles16)     echo "registry.suse.com/bci/bci-base:16.0|sles" ;;
        debian11)   echo "debian:11|deb" ;;
        debian12)   echo "debian:12|deb" ;;
        debian13)   echo "debian:13|deb" ;;
        ubuntu2204) echo "ubuntu:22.04|deb" ;;
        ubuntu2404) echo "ubuntu:24.04|deb" ;;
        ubuntu2604) echo "ubuntu:26.04|deb" ;;
        # An apk is tied to the musl and library sonames of the Alpine release it
        # was built on, so unlike rpm/deb it cannot be carried to a newer one --
        # hence one target per Alpine version that nginx also publishes for.
        alpine321)  echo "alpine:3.21|apk" ;;
        alpine322)  echo "alpine:3.22|apk" ;;
        alpine323)  echo "alpine:3.23|apk" ;;
        alpine324)  echo "alpine:3.24|apk" ;;
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
        --without)   DISABLED="$DISABLED $2"; shift 2 ;;
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

# Downloads (or reuses) the pinned dependency sources and wraps them into one
# tarball that the rpm/deb/apk recipes take as a single extra source.
make_deps_tarball() {
    DEPS_TARBALL="$OUTDIR/tengine-deps.tar.gz"

    sh "$SELF_DIR/fetch-deps.sh" --outdir "$OUTDIR/deps"

    stage="$OUTDIR/.deps-stage"
    rm -rf "$stage"
    mkdir -p "$stage/deps"
    cp "$OUTDIR"/deps/*.tar.gz "$stage/deps/"

    info "staging dependency sources -> $DEPS_TARBALL"
    tar -czf "$DEPS_TARBALL" -C "$stage" deps
    rm -rf "$stage"
}

# Translates --without switches into build-deps.sh / rpmbuild arguments.
deps_disable_args() {
    for f in $DISABLED; do
        printf ' --without-%s' "$f"
    done
}

# ------------------------------------------------------------------ rpm build

# Is a CMake >= 3.5 reachable on PATH? Deliberately mirrors build-deps.sh's
# find_cmake, since that is the code which will actually run it.
cmake_binary_ok() {
    for c in cmake3 cmake; do
        command -v "$c" >/dev/null 2>&1 || continue
        v=$("$c" --version 2>/dev/null | head -n 1 | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')
        [ -n "$v" ] || continue
        if [ "$(printf '%s\n3.5\n' "$v" | sort -V | head -n 1)" = "3.5" ]; then
            echo yes
            return
        fi
    done
    echo no
}

# Does rpm itself own a CMake new enough for the spec's BuildRequires? `rpm -q`
# prints "package foo is not installed" on stdout and exits non-zero, hence both
# the `||` and the leading-digit check.
cmake_rpm_ok() {
    for p in cmake3 cmake; do
        v=$(rpm -q --qf '%{VERSION}\n' "$p" 2>/dev/null | head -n 1) || continue
        case "$v" in [0-9]*) ;; *) continue ;; esac
        if [ "$(printf '%s\n3.5\n' "$v" | sort -V | head -n 1)" = "3.5" ]; then
            echo yes
            return
        fi
    done
    echo no
}

build_rpm() {
    command -v rpmbuild >/dev/null || die "rpmbuild not found (install rpm-build)"
    make_tarball
    make_deps_tarball

    rpmtop="$OUTDIR/rpmbuild"
    rm -rf "$rpmtop"
    mkdir -p "$rpmtop/BUILD" "$rpmtop/BUILDROOT" "$rpmtop/RPMS" \
             "$rpmtop/SRPMS" "$rpmtop/SOURCES" "$rpmtop/SPECS"
    cp "$TARBALL" "$DEPS_TARBALL" "$rpmtop/SOURCES/"
    cp "$SELF_DIR/rpm/tengine.spec" "$rpmtop/SPECS/"

    # Rich dependencies -- "(a or b)" -- need rpm >= 4.13. Ask the running rpm
    # instead of inferring it from the distro release, because el7-era
    # derivatives do not consistently define %rhel.
    #
    # `rpm --eval '%{rpmversion}'` is not usable here: on el7-era rpm the macro
    # is undefined and --eval echoes it back verbatim while still exiting 0, so
    # a `|| echo 0` fallback never fires. `rpm --version` prints
    # "RPM version X.Y.Z" everywhere; anything not starting with a digit is
    # treated as "too old" so the safe pcre-devel branch wins.
    rpmver=$(rpm --version 2>/dev/null | awk '{print $NF}')
    case "$rpmver" in
        [0-9]*) ;;
        *)      rpmver=0 ;;
    esac

    if [ "$(printf '%s\n4.13\n' "$rpmver" | sort -V | head -n 1)" = "4.13" ]; then
        rich_deps=1
    else
        rich_deps=0
        info "rpm $rpmver predates rich dependencies; requiring pcre-devel"
    fi

    set -- --define "_topdir $rpmtop" \
           --define "tengine_version $TENGINE_VERSION" \
           --define "build_ts $BUILD_TS" \
           --define "have_rich_deps $rich_deps"

    # The spec's CMake BuildRequires can only be satisfied by an rpm-managed
    # CMake. A usable one installed some other way (pip, upstream tarball,
    # /usr/local) is invisible to rpm, which would fail the build even though
    # build-deps.sh can use it happily -- some el7 derivatives package only
    # cmake 2.8 while carrying a much newer one on PATH. Detect that and drop
    # only the CMake requirement, rather than all of them.
    if [ "$(cmake_binary_ok)" = yes ] && [ "$(cmake_rpm_ok)" = no ]; then
        info "usable CMake found on PATH but not owned by rpm; skipping its BuildRequires"
        set -- "$@" --with external_cmake
    fi
    if [ -n "$DIST_TAG" ]; then
        set -- "$@" --define "dist $DIST_TAG"
    fi
    for f in $FEATURES; do
        set -- "$@" --with "$f"
    done
    for f in $DISABLED; do
        set -- "$@" --without "$f"
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
    make_deps_tarball

    work="$OUTDIR/debbuild"
    debtop="$work/tengine-$TENGINE_VERSION"

    suite=unstable
    if [ -r /etc/os-release ]; then
        suite=$(. /etc/os-release; echo "${VERSION_CODENAME:-unstable}")
    fi

    # The distro codename belongs in the version: neither the deb version nor
    # the file name carries one otherwise, so debian11/debian12/ubuntu2204/
    # ubuntu2404 would all produce a byte-identical file name and apt could not
    # tell the builds apart. "~" sorts lower than no suffix at all, which is the
    # Debian convention for this.
    debversion="$TENGINE_VERSION-$BUILD_TS~$suite"

    rm -rf "$work"
    mkdir -p "$work"
    tar -xzf "$TARBALL" -C "$work"
    # debian/rules reads the dependency sources from deps/ in the source tree.
    tar -xzf "$DEPS_TARBALL" -C "$debtop"

    cp -R "$SELF_DIR/deb/debian" "$debtop/debian"
    cp "$SELF_DIR/conf/tengine.service"   "$debtop/debian/tengine.service"
    cp "$SELF_DIR/conf/tengine.logrotate" "$debtop/debian/tengine.logrotate"

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

    # Ubuntu's debhelper names the automatic debug-symbol package
    # tengine-dbgsym_*.ddeb while Debian's uses a plain .deb, so a glob for
    # .deb alone silently drops the symbols on every Ubuntu target.
    find "$work" -maxdepth 1 \( -name '*.deb' -o -name '*.ddeb' \) \
        -exec cp {} "$OUTDIR/" \;
    [ "$KEEP_BUILDDIR" = yes ] || rm -rf "$work"
    info "artifacts:"
    ls -1 "$OUTDIR"/*.deb "$OUTDIR"/*.ddeb 2>/dev/null
}

# ------------------------------------------------------------------ apk build

build_apk() {
    command -v abuild >/dev/null || die "abuild not found (apk add alpine-sdk)"
    make_tarball
    make_deps_tarball

    work="$OUTDIR/apkbuild"
    rm -rf "$work"
    mkdir -p "$work"

    cp "$SELF_DIR/apk/APKBUILD" "$SELF_DIR/apk/tengine.pre-install" \
        "$SELF_DIR/apk/tengine.post-install" "$work/"
    cp "$SELF_DIR/conf/tengine.openrc" "$SELF_DIR/conf/tengine.logrotate" \
       "$SELF_DIR/conf/tengine.conf" "$work/"
    cp "$SELF_DIR/conf/conf.d/default.conf" "$work/"
    cp "$TARBALL" "$DEPS_TARBALL" "$work/"

    # pkgver carries the build timestamp as an apk post-release suffix so
    # repeated builds of one upstream version stay distinguishable.
    sed -e "s|^_upstream_ver=.*|_upstream_ver=$TENGINE_VERSION|" \
        -e "s|^pkgver=.*|pkgver=${TENGINE_VERSION}_p${BUILD_TS}|" \
        "$work/APKBUILD" > "$work/APKBUILD.new"
    mv "$work/APKBUILD.new" "$work/APKBUILD"

    # -i would install the public key through doas, which the alpine build image
    # does not carry; the build runs as root, so place it directly instead.
    if [ ! -f "$HOME/.abuild/abuild.conf" ]; then
        abuild-keygen -a -n
        cp "$HOME"/.abuild/*.rsa.pub /etc/apk/keys/
    fi
    REPODEST="$work/repo"
    export REPODEST

    # Both invocations need -F: abuild refuses to run as root without it, and
    # the container build has no unprivileged user to drop to.
    info "abuild tengine-${TENGINE_VERSION}_p${BUILD_TS}"
    ( cd "$work" && abuild -F checksum && abuild -F -r )

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
#
# The full feature set adds three build-time needs on every platform: CMake
# (>= 3.5, for xquic), a C++ compiler (xquic links libstdc++) and Perl (Tongsuo
# configures itself with it). curl is needed to fetch the dependency sources
# when the caller did not prime <outdir>/deps beforehand.
bootstrap_cmd() {
    case "$1" in
        rpm)
            cat <<'EOS'
if command -v dnf >/dev/null 2>&1; then
    if dnf -q list pcre2-devel >/dev/null 2>&1; then _pcre=pcre2-devel; else _pcre=pcre-devel; fi
    # el9 images carry curl-minimal, which conflicts with the full curl package.
    # It provides /usr/bin/curl all the same, so only ask for curl when the image
    # has none -- replacing it would drag the whole dependency chain along.
    _curl=curl
    command -v curl >/dev/null 2>&1 && _curl=
    # Tongsuo's Configure pulls in a handful of Perl modules that every distro
    # splits up differently -- and on el8 "perl-FindBin" is hidden behind a
    # module stream, so asking for the package name gets filtered out entirely.
    # Requesting the perl(...) virtual provides instead lets rpm resolve each
    # module to whatever package happens to carry it.
    dnf -y install rpm-build gcc gcc-c++ make cmake tar findutils diffutils $_curl \
        perl "perl(FindBin)" "perl(IPC::Cmd)" "perl(lib)" \
        openssl-devel zlib-devel systemd "$_pcre"
else
    # CentOS 7 is EOL; its mirrors moved to vault.centos.org
    sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
           -e 's|^#*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' \
           /etc/yum.repos.d/CentOS-*.repo
    # perl-core drags in the full set of core modules. Tongsuo's Configure and
    # its generated Makefile reach for several of them (IPC::Cmd, Data::Dumper,
    # ...) and el7 splits every one into its own package, so pulling them in
    # one by one just moves the failure to the next module.
    yum -y install rpm-build gcc gcc-c++ make tar findutils diffutils curl \
        perl-core openssl-devel zlib-devel pcre-devel systemd
    # el7 packages CMake 2.8 and xquic needs >= 3.5. The usual answer, cmake3,
    # lives only in EPEL 7 -- itself EOL, with a dead metalink and nothing but
    # an archive mirror left, so pulling it in means rewriting a second set of
    # repo files. Kitware's own build is a static tarball needing just glibc
    # 2.17, which el7 has. build.sh detects that rpm does not own this CMake
    # and drops the matching BuildRequires by itself.
    curl -fsSL "https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-linux-$(uname -m).tar.gz" \
        | tar xz --strip-components=1 -C /usr/local
    cmake --version
fi
EOS
            ;;
        sles)
            echo 'zypper --non-interactive --no-gpg-checks install rpm-build gcc gcc-c++ make cmake tar findutils curl perl libopenssl-devel zlib-devel pcre2-devel systemd-rpm-macros'
            ;;
        deb)
            echo 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y --no-install-recommends build-essential debhelper cmake perl curl ca-certificates libssl-dev zlib1g-dev libpcre2-dev'
            ;;
        apk)
            echo 'apk add --no-cache alpine-sdk cmake perl curl linux-headers openssl-dev pcre2-dev zlib-dev'
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

    # The SUSE and openEuler images leave %dist empty, so their packages come out
    # as tengine-<ver>-<ts>.<arch>.rpm with nothing naming the target -- two
    # different distributions producing the same file name once a release
    # directory is assembled. Give them one unless the caller asked for its own.
    # Anolis is deliberately absent: its images do define %dist (an8 packages
    # ship as ...-<ts>.an8.<arch>.rpm), so anolis8 and anolis23 already differ.
    target_dist=""
    if [ -z "$DIST_TAG" ]; then
        case "$target" in
            sles15)        target_dist=".sles15" ;;
            sles16)        target_dist=".sles16" ;;
            openeuler2203) target_dist=".oe2203" ;;
            openeuler2403) target_dist=".oe2403" ;;
        esac
    fi

    inner="--outdir /out --timestamp $BUILD_TS"
    if [ -n "$DIST_TAG" ]; then
        inner="$inner --dist $DIST_TAG"
    elif [ -n "$target_dist" ]; then
        inner="$inner --dist $target_dist"
    fi
    for f in $FEATURES; do
        inner="$inner --with $f"
    done
    for f in $DISABLED; do
        inner="$inner --without $f"
    done

    set -- run --rm
    if [ -n "$PLATFORM" ]; then
        set -- "$@" --platform "$PLATFORM"
    fi
    set -- "$@" -v "$SRC_ROOT:/src:ro" -v "$OUTDIR:/out" -w / "$image"

    # Pull up front rather than letting `run` do it implicitly: a full matrix
    # makes dozens of anonymous registry pulls, and a timeout or a rate limit
    # would otherwise fail the target outright. Retry with a growing pause; a
    # tag that genuinely does not exist fails all attempts and still reports.
    pull_delay=5
    pull_attempt=1
    while :; do
        if [ -n "$PLATFORM" ]; then
            "$engine" pull --platform "$PLATFORM" "$image" && break
        else
            "$engine" pull "$image" && break
        fi
        [ "$pull_attempt" -lt 3 ] || die "[$target] cannot pull $image (3 attempts)"
        info "[$target] pull of $image failed, retrying in ${pull_delay}s"
        sleep "$pull_delay"
        pull_attempt=$((pull_attempt + 1))
        pull_delay=$((pull_delay * 3))
    done

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
        # Prime the dependency cache on the host: --outdir is bind mounted into
        # every container as /out, so the targets all reuse this one download
        # instead of racing to fetch the same tarballs.
        sh "$SELF_DIR/fetch-deps.sh" --outdir "$OUTDIR/deps"

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
