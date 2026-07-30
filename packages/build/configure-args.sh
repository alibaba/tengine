#!/bin/sh
#
# Single source of truth for the configure arguments used by every distro
# package (RPM / DEB / APK).  Keeping one copy guarantees that a tengine
# package built on RHEL ships exactly the same feature set and the same
# filesystem layout as the one built on Alpine.
#
# The script prints one configure argument per line so callers can do:
#
#     ./configure $(sh packages/build/configure-args.sh) \
#         --with-cc-opt="..." --with-ld-opt="..."
#
# Arguments that may contain whitespace (--with-cc-opt / --with-ld-opt) are
# deliberately NOT emitted here; the per-distro recipe appends them because
# only it knows the distro hardening flags.
#
# Environment overrides (all optional):
#
#   TENGINE_LIBDIR          dir holding dynamic modules   [/usr/lib]
#   TENGINE_WITH_BACKTRACE  yes|no  ngx_backtrace_module  [yes]
#                           must be "no" on musl (no backtrace() in libc)
#   TENGINE_WITH_ZSTD       yes|no  ngx_zstd module       [no]  needs libzstd
#   TENGINE_WITH_LUA        yes|no  ngx_http_lua_module   [no]  needs LuaJIT 2.1
#   TENGINE_WITH_GEOIP      yes|no  stream geoip module   [no]  needs libGeoIP
#   TENGINE_WITH_MAIL       yes|no  mail proxy modules    [yes]
#   TENGINE_WITH_PCRE_JIT   yes|no  PCRE JIT compilation  [yes]
#

set -e

: "${TENGINE_LIBDIR:=/usr/lib}"
: "${TENGINE_WITH_BACKTRACE:=yes}"
: "${TENGINE_WITH_ZSTD:=no}"
: "${TENGINE_WITH_LUA:=no}"
: "${TENGINE_WITH_GEOIP:=no}"
: "${TENGINE_WITH_MAIL:=yes}"
: "${TENGINE_WITH_PCRE_JIT:=yes}"

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
# Tengine modules.  Only modules whose sole build dependencies are
# pcre/openssl/zlib are enabled unconditionally -- anything needing an extra
# library stays behind a switch so a plain `rpmbuild` on a stock RHEL box
# still succeeds.
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
[ "$TENGINE_WITH_LUA" = yes ] && \
    TENGINE_MODULES="$TENGINE_MODULES ngx_http_lua_module"

for _mod in $TENGINE_MODULES; do
    echo "--add-module=./modules/${_mod}"
done

echo "--without-http_upstream_keepalive_module"
