#!/bin/sh
#
# Single source of truth for the configure arguments used by every distro
# package (RPM / DEB / APK).  Keeping one copy guarantees that a tengine
# package built on RHEL ships exactly the same feature set and the same
# filesystem layout as the one built on Alpine.
#
# The script prints one configure argument per line so callers can do:
#
#     . dist/deps-build/deps-env.sh                       # from build-deps.sh
#     ./configure $(sh packages/build/configure-args.sh) \
#         --with-cc-opt="..." \
#         --with-ld-opt="... $(sh packages/build/configure-args.sh --print-ld-opt)" \
#         --with-openssl-opt="$(sh packages/build/configure-args.sh --print-openssl-opt)"
#
# Arguments that may contain whitespace are deliberately NOT part of the plain
# output, because callers word-split it.  The two that the full feature set
# needs are available through --print-ld-opt / --print-openssl-opt instead, so
# they still have a single definition; --with-cc-opt stays with the per-distro
# recipe, which is the only thing that knows the distro hardening flags.
#
# Tongsuo, xquic and Lua are all built from pinned sources by
# packages/build/build-deps.sh, which writes the paths below into deps-env.sh.
#
# Environment overrides (all optional):
#
#   TENGINE_LIBDIR          dir holding dynamic modules   [/usr/lib]
#   TENGINE_WITH_BACKTRACE  yes|no  ngx_backtrace_module  [yes]
#                           must be "no" on musl (no backtrace() in libc)
#   TENGINE_WITH_TONGSUO    yes|no  Tongsuo + NTLS        [yes] needs TONGSUO_SRC
#   TENGINE_WITH_XQUIC      yes|no  QUIC / HTTP-3         [yes] needs Tongsuo
#   TENGINE_WITH_LUA        yes|no  ngx_http_lua_module   [yes] needs LuaJIT 2.1
#   TENGINE_WITH_ZSTD       yes|no  ngx_zstd module       [no]  needs libzstd
#   TENGINE_WITH_GEOIP      yes|no  stream geoip module   [no]  needs libGeoIP
#   TENGINE_WITH_MAIL       yes|no  mail proxy modules    [yes]
#   TENGINE_WITH_PCRE_JIT   yes|no  PCRE JIT compilation  [yes]
#
#   TENGINE_TONGSUO_SRC     Tongsuo source tree for --with-openssl
#   TENGINE_XQUIC_INC       xquic headers
#   TENGINE_XQUIC_LIB       directory holding the freshly built libxquic.so
#   TENGINE_XQUIC_RPATH     where libxquic.so will live once installed
#                                                  [<libdir>/tengine]
#

set -e

: "${TENGINE_LIBDIR:=/usr/lib}"
: "${TENGINE_WITH_BACKTRACE:=yes}"
: "${TENGINE_WITH_TONGSUO:=yes}"
: "${TENGINE_WITH_XQUIC:=yes}"
: "${TENGINE_WITH_LUA:=yes}"
: "${TENGINE_WITH_ZSTD:=no}"
: "${TENGINE_WITH_GEOIP:=no}"
: "${TENGINE_WITH_MAIL:=yes}"
: "${TENGINE_WITH_PCRE_JIT:=yes}"

# Private directory for the libraries this package brings along (libxquic.so,
# libluajit) plus the compiled Lua C modules.
TENGINE_PRIVATE_LIBDIR="${TENGINE_LIBDIR}/tengine"
: "${TENGINE_XQUIC_RPATH:=$TENGINE_PRIVATE_LIBDIR}"

die() { printf 'configure-args.sh: error: %s\n' "$*" >&2; exit 1; }

#
# Whitespace-carrying arguments, printed on demand.
#
case "${1:-}" in
    --print-openssl-opt)
        # --api=1.1.1 keeps the deprecated 1.1.1 API visible (Tengine still
        # uses parts of it); enable-ntls is what ngx_tongsuo_ntls needs.
        [ "$TENGINE_WITH_TONGSUO" = yes ] && printf '%s' '--api=1.1.1 enable-ntls'
        exit 0
        ;;
    --print-ld-opt)
        # libxquic.so and libluajit ship inside the package, outside the
        # default linker search path.
        if [ "$TENGINE_WITH_XQUIC" = yes ] || [ "$TENGINE_WITH_LUA" = yes ]; then
            printf '%s' "-Wl,-rpath,$TENGINE_PRIVATE_LIBDIR"
        fi
        exit 0
        ;;
    "") ;;
    *)  die "unknown option: $1" ;;
esac

#
# Filesystem layout.  Identical on every distro except for libdir, so that
# operators can move between platforms without relearning the paths.
#
#   binary   /usr/sbin/tengine
#   config   /etc/tengine/tengine.conf   (+ /etc/tengine/conf.d/*.conf)
#   logs     /var/log/tengine/{access,error}.log
#   pid      /run/tengine.pid
#   modules  $TENGINE_LIBDIR/tengine/modules
#
cat <<EOF
--prefix=/usr/share/tengine
--sbin-path=/usr/sbin/tengine
--modules-path=${TENGINE_LIBDIR}/tengine/modules
--conf-path=/etc/tengine/tengine.conf
--error-log-path=/var/log/tengine/error.log
--http-log-path=/var/log/tengine/access.log
--pid-path=/run/tengine.pid
--lock-path=/run/lock/tengine.lock
--http-client-body-temp-path=/var/cache/tengine/client_temp
--http-proxy-temp-path=/var/cache/tengine/proxy_temp
--http-fastcgi-temp-path=/var/cache/tengine/fastcgi_temp
--http-uwsgi-temp-path=/var/cache/tengine/uwsgi_temp
--http-scgi-temp-path=/var/cache/tengine/scgi_temp
--user=tengine
--group=tengine
EOF

# Core nginx features.
cat <<'EOF'
--with-threads
--with-file-aio
--with-compat
--with-http_ssl_module
--with-http_v2_module
--with-http_realip_module
--with-http_addition_module
--with-http_auth_request_module
--with-http_dav_module
--with-http_flv_module
--with-http_gunzip_module
--with-http_gzip_static_module
--with-http_mp4_module
--with-http_random_index_module
--with-http_secure_link_module
--with-http_stub_status_module
--with-http_sub_module
--with-stream
--with-stream_ssl_module
--with-stream_realip_module
--with-stream_ssl_preread_module
--with-stream_sni
EOF

[ "$TENGINE_WITH_PCRE_JIT" = yes ] && echo "--with-pcre-jit"

if [ "$TENGINE_WITH_MAIL" = yes ]; then
    echo "--with-mail"
    echo "--with-mail_ssl_module"
fi

[ "$TENGINE_WITH_GEOIP" = yes ] && echo "--with-stream_geoip_module"

#
# Tongsuo.  ngx_tongsuo_ntls only defines T_NGX_SSL_NTLS when USE_OPENSSL is
# set, i.e. NTLS is only reachable through --with-openssl against a Tongsuo
# source tree -- a system OpenSSL cannot provide it.  The tree is prepared by
# build-deps.sh, which also hands the same Tongsuo to xquic.
#
if [ "$TENGINE_WITH_TONGSUO" = yes ]; then
    [ -n "${TENGINE_TONGSUO_SRC:-}" ] || \
        die "TENGINE_WITH_TONGSUO=yes but TENGINE_TONGSUO_SRC is unset (run build-deps.sh first)"
    [ -d "$TENGINE_TONGSUO_SRC" ] || \
        die "TENGINE_TONGSUO_SRC=$TENGINE_TONGSUO_SRC is not a directory"
    echo "--with-openssl=$TENGINE_TONGSUO_SRC"
fi

#
# xquic.  --with-xquic-rpath keeps the recorded runtime path pointing at the
# installed libxquic.so instead of this build's scratch directory.
#
if [ "$TENGINE_WITH_XQUIC" = yes ]; then
    [ "$TENGINE_WITH_TONGSUO" = yes ] || \
        die "TENGINE_WITH_XQUIC=yes requires TENGINE_WITH_TONGSUO=yes (SSL_TYPE=babassl)"
    [ -n "${TENGINE_XQUIC_INC:-}" ] && [ -n "${TENGINE_XQUIC_LIB:-}" ] || \
        die "TENGINE_WITH_XQUIC=yes but TENGINE_XQUIC_INC/LIB are unset (run build-deps.sh first)"
    echo "--with-xquic-inc=$TENGINE_XQUIC_INC"
    echo "--with-xquic-lib=$TENGINE_XQUIC_LIB"
    echo "--with-xquic-rpath=$TENGINE_XQUIC_RPATH"
fi

#
# Tengine modules.  Anything needing a library that no distro ships is built
# from pinned sources by build-deps.sh (Tongsuo, xquic, LuaJIT); the remaining
# switches below cover libraries that a plain `rpmbuild` on a stock box cannot
# be assumed to have.
#
# ngx_http_upstream_keepalive_module is Tengine's own reimplementation, so the
# stock nginx one has to be turned off to avoid a duplicate directive clash.
#
TENGINE_MODULES="
ngx_debug_pool
ngx_debug_timer
ngx_debug_conn
ngx_http_concat_module
ngx_http_footer_filter_module
ngx_http_proxy_connect_module
ngx_http_reqstat_module
ngx_http_slice_module
ngx_http_sysguard_module
ngx_http_trim_filter_module
ngx_http_upstream_check_module
ngx_http_upstream_consistent_hash_module
ngx_http_upstream_dynamic_module
ngx_http_upstream_dyups_module
ngx_http_upstream_iwrr_module
ngx_http_upstream_keepalive_module
ngx_http_upstream_session_sticky_module
ngx_http_upstream_vnswrr_module
ngx_http_user_agent_module
ngx_multi_upstream_module
ngx_slab_stat
"

[ "$TENGINE_WITH_BACKTRACE" = yes ] && \
    TENGINE_MODULES="ngx_backtrace_module $TENGINE_MODULES"
[ "$TENGINE_WITH_ZSTD" = yes ] && \
    TENGINE_MODULES="$TENGINE_MODULES ngx_zstd"
[ "$TENGINE_WITH_TONGSUO" = yes ] && \
    TENGINE_MODULES="$TENGINE_MODULES ngx_tongsuo_ntls"
# Keep lua ahead of xquic: ngx_http_xquic_module's config pulls
# ../ngx_http_lua_module/src into CORE_INCS, so the two travel together.
[ "$TENGINE_WITH_LUA" = yes ] && \
    TENGINE_MODULES="$TENGINE_MODULES ngx_http_lua_module"
[ "$TENGINE_WITH_XQUIC" = yes ] && \
    TENGINE_MODULES="$TENGINE_MODULES ngx_http_xquic_module"

for _mod in $TENGINE_MODULES; do
    echo "--add-module=./modules/${_mod}"
done

echo "--without-http_upstream_keepalive_module"
