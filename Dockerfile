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
# Both stages are parameterised so the image can be rebased, e.g.
#     --build-arg BASE_IMAGE=openanolis/anolisos:8.8 \
#     --build-arg RUNTIME_IMAGE=openanolis/anolisos:8.8
# (a non-Debian base needs its own package manager commands, though -- see
# Dockerfile.alpine for the musl variant).
#

ARG BASE_IMAGE=debian:12
ARG RUNTIME_IMAGE=debian:12-slim

FROM ${BASE_IMAGE} AS builder

# cmake + g++ are for xquic, perl configures Tongsuo, curl fetches the pinned
# dependency tarballs.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
        build-essential cmake perl curl ca-certificates \
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
    ./configure \
        $(sh packages/build/configure-args.sh) \
        --with-cc-opt="-Wno-error" \
        --with-ld-opt="$(sh packages/build/configure-args.sh --print-ld-opt)" \
        --with-openssl-opt="$(sh packages/build/configure-args.sh --print-openssl-opt)"; \
    make -j"$(nproc)"; \
    make install DESTDIR=/out; \
    cp -a /tmp/deps-staging/. /out/

# Same post-install fixups as the distro packages: ship the packaged
# tengine.conf instead of the stock nginx.conf, resolve the libdir placeholder
# in lua_package_cpath, and drop /run (a tmpfs at runtime).
RUN set -eux; \
    rm -f /out/etc/tengine/*.default; \
    install -p -m 0644 packages/build/conf/tengine.conf /out/etc/tengine/tengine.conf; \
    install -d -m 0755 /out/etc/tengine/conf.d; \
    install -p -m 0644 packages/build/conf/conf.d/default.conf /out/etc/tengine/conf.d/default.conf; \
    sed -i -e 's|@TENGINE_LIBDIR@|/usr/lib|g' /out/etc/tengine/tengine.conf; \
    rm -rf /out/run /out/var/run


FROM ${RUNTIME_IMAGE}

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
