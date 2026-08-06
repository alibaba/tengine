#
# Tengine container image, Debian flavour (the default).
#
# Multi stage: the builder compiles the pinned third-party dependencies
# (Tongsuo for NTLS, xquic for QUIC/HTTP-3, LuaJIT plus the resty Lua
# libraries) and Tengine itself, the runtime stage keeps only the installed
# tree plus the shared libraries it needs.
#
# The configure arguments come from packages/build/configure-args.sh, the same
# file the rpm/deb/apk recipes use, so the image and the distro packages ship an
# identical feature set and filesystem layout.
#
#     docker build -t tengine .
#     docker run --rm -p 8080:80 tengine
#
# Two variants are built from this file, mirroring how the nginx official
# images are published:
#
#     docker build -t tengine .                        # default
#     docker build -t tengine:perl --target perl .     # + ngx_http_perl_module
#
# There is only ever ONE compile. ngx_http_perl_module is always built, as a
# dynamic module, and its two files are set aside in /out-perl by the builder;
# the default runtime simply does not copy them. So the perl variant costs a
# `perl` runtime package and a few hundred KB rather than a second 90-minute
# build, and both variants share every builder layer in the buildx cache.
#
# A side effect worth knowing: `tengine -V` in the DEFAULT image lists
# --with-http_perl_module=dynamic even though the .so is not there. That is the
# same thing nginx's own images do -- their slim variants advertise dynamic
# modules they do not ship, because one build feeds every variant.
#
# Both stages are parameterised so the image can be rebased, e.g.
#     --build-arg BASE_IMAGE=openanolis/anolisos:8.8 \
#     --build-arg RUNTIME_IMAGE=openanolis/anolisos:8.8
# (a non-Debian base needs its own package manager commands, though -- see
# Dockerfile.alpine for the musl variant).
#

# Debian 13 is "trixie", the same base the nginx official images use.
# .github/scripts/image-tags.sh parses the release number out of BASE_IMAGE and
# maps it to the codename used in the "-trixie" style image tags -- when bumping
# this, keep the "debian:<release>" shape and add the codename to that map.
ARG BASE_IMAGE=debian:13
ARG RUNTIME_IMAGE=debian:13-slim

FROM ${BASE_IMAGE} AS builder

# cmake + g++ are for xquic, perl configures Tongsuo, curl fetches the pinned
# dependency tarballs. libperl-dev carries the perl headers and
# ExtUtils::Embed, which auto/lib/perl/conf refuses to build without.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
        build-essential cmake perl libperl-dev curl ca-certificates \
        libssl-dev zlib1g-dev libpcre2-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/tengine
COPY . .

# --libdir is the *installed* location on purpose: ngx_http_xquic_module
# records it as libxquic.so's runtime path, so it must not point at this
# throwaway build tree.
RUN set -eux; \
    sh packages/build/fetch-deps.sh --outdir /tmp/deps; \
    sh packages/build/build-deps.sh \
        --srcdir /tmp/deps \
        --workdir /tmp/deps-build \
        --staging /tmp/deps-staging \
        --libdir /usr/lib/tengine \
        --datadir /usr/share/tengine

# The tree appends -Werror in auto/cc/gcc; with an arbitrary compiler version
# that is a guaranteed build break, so relax it here as the packages do.
RUN set -eux; \
    . /tmp/deps-build/deps-env.sh; \
    export TENGINE_LIBDIR=/usr/lib; \
    export TENGINE_WITH_PERL=yes; \
    ./configure \
        $(sh packages/build/configure-args.sh) \
        --with-cc-opt="-Wno-error" \
        --with-ld-opt="$(sh packages/build/configure-args.sh --print-ld-opt)" \
        --with-openssl-opt="$(sh packages/build/configure-args.sh --print-openssl-opt)"; \
    make -j"$(nproc)"; \
    make install DESTDIR=/out; \
    cp -a /tmp/deps-staging/. /out/

# Same post-install fixups as the distro packages: ship the packaged
# tengine.conf instead of the in-tree one, resolve the libdir placeholder
# in lua_package_cpath, and drop /run (a tmpfs at runtime).
RUN set -eux; \
    rm -f /out/etc/tengine/*.default; \
    install -p -m 0644 packages/build/conf/tengine.conf /out/etc/tengine/tengine.conf; \
    install -d -m 0755 /out/etc/tengine/conf.d; \
    install -p -m 0644 packages/build/conf/conf.d/default.conf /out/etc/tengine/conf.d/default.conf; \
    sed -i -e 's|@TENGINE_LIBDIR@|/usr/lib|g' /out/etc/tengine/tengine.conf; \
    rm -rf /out/run /out/var/run

# Move the perl module out of the default tree so only the "perl" stage picks
# it up.
#
# The .so is placed by nginx's own install rule, which honours DESTDIR, so it is
# under /out as expected. nginx.pm is NOT: auto/install delegates it to
# `$(MAKE) install` inside the generated MakeMaker tree, and that copy does not
# reliably land under DESTDIR. Take it straight from blib instead -- pm_to_blib
# is a plain product of the build that already has %%VERSION%% substituted, so
# this is both more direct and independent of MakeMaker's install semantics.
#
# Whatever MakeMaker did drop under /out (man3, .packlist, the arch directory)
# is build bookkeeping the images do not ship, hence the rm.
RUN set -eux; \
    find /out -name 'nginx.pm' -o -name 'ngx_http_perl_module.so' | sort; \
    install -d /out-perl/usr/lib/tengine/modules; \
    mv /out/usr/lib/tengine/modules/ngx_http_perl_module.so \
       /out-perl/usr/lib/tengine/modules/; \
    install -d /out-perl/usr/lib/tengine/perl; \
    install -m 0644 objs/src/http/modules/perl/blib/lib/nginx.pm \
        /out-perl/usr/lib/tengine/perl/nginx.pm; \
    rm -rf /out/usr/lib/tengine/perl


FROM ${RUNTIME_IMAGE} AS runtime

ARG TENGINE_VERSION=dev
LABEL org.opencontainers.image.title="Tengine" \
      org.opencontainers.image.description="Tengine web server with Tongsuo (NTLS), xquic (QUIC/HTTP-3) and Lua" \
      org.opencontainers.image.version="${TENGINE_VERSION}" \
      org.opencontainers.image.url="https://tengine.taobao.org/" \
      org.opencontainers.image.source="https://github.com/alibaba/tengine" \
      org.opencontainers.image.licenses="BSD-2-Clause AND Apache-2.0 AND MIT"

# libstdc++6 is required because libxquic links against it. Tongsuo is linked
# statically, so no OpenSSL runtime package is needed.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
        libpcre2-8-0 zlib1g libstdc++6 ca-certificates tzdata; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd -r tengine; \
    useradd -r -g tengine -s /usr/sbin/nologin -d /var/cache/tengine \
        -c "Tengine web server" tengine

COPY --from=builder /out/ /

RUN set -eux; \
    install -d -m 0755 -o tengine -g tengine /var/log/tengine; \
    install -d -m 0700 -o tengine -g tengine /var/cache/tengine; \
    ln -sf /dev/stdout /var/log/tengine/access.log; \
    ln -sf /dev/stderr /var/log/tengine/error.log; \
    /usr/sbin/tengine -t

# 443/udp carries QUIC / HTTP-3.
EXPOSE 80 443 443/udp

# SIGQUIT is Tengine's graceful shutdown signal.
STOPSIGNAL SIGQUIT

CMD ["/usr/sbin/tengine", "-g", "daemon off;"]


# --------------------------------------------------------------- perl variant
#
# Adds ngx_http_perl_module and a perl runtime. Unlike the nginx official perl
# image, which only drops the module in and leaves loading it to the operator,
# the load_module line is prepended here -- so `perl_set` and friends work out
# of the box, and the `tengine -t` below actually proves the module loads
# instead of merely proving the file exists.
#
# perl (not just perl-base) is what pulls in libperl.so.*, which the module
# links against.
FROM runtime AS perl

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends perl; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /out-perl/ /

# load_module is only valid in the main context, and the packaged tengine.conf
# has no include there, so prepend it to the file itself. printf+cat rather
# than `sed -i 1i` to stay identical to the Alpine image, whose BusyBox sed
# does not expand \n in inserted text.
RUN set -eux; \
    { printf 'load_module /usr/lib/tengine/modules/ngx_http_perl_module.so;\n\n'; \
      cat /etc/tengine/tengine.conf; } > /tmp/tengine.conf; \
    cat /tmp/tengine.conf > /etc/tengine/tengine.conf; \
    rm -f /tmp/tengine.conf; \
    /usr/sbin/tengine -t


# ------------------------------------------------------------ default variant
#
# Last stage on purpose: a plain `docker build .` with no --target has to keep
# producing the default image, not the perl one. Nothing is added here; the
# alias exists so `--target default` also works.
FROM runtime AS default
