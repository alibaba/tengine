#!/bin/sh

# Configure tengine with the widest module set that needs nothing beyond
# pcre2/zlib/openssl, so that a compiler diagnostic anywhere in the tree is
# actually reached. Shared by the three jobs in
# .github/workflows/compiler-warnings.yml, which differ only in the compiler
# ($CC) and in the flags handed over in $NGX_EXTRA_CC_OPT.
#
# Coverage over dependencies is the trade deliberately made here: the point of
# these jobs is breadth of compiled source, and every extra library is another
# way for the job to go red for reasons that have nothing to do with warnings.
# Left out for that reason, each needing a library the workflow does not
# install: --with-http_{xslt,image_filter,geoip,perl}_module,
# --with-stream_geoip_module, ngx_http_lua_module (luajit2),
# ngx_http_xquic_module (xquic), ngx_zstd (libzstd), ngx_tongsuo_ntls
# (Tongsuo), ngx_ingress_module (libprotobuf-c), ngx_http_tfs_module (libyajl).
# The first group of those is covered by the strict-release job, which builds
# the pinned dependency stack; ngx_ingress_module and ngx_http_tfs_module are
# compiled by nothing at all.
#
# --with-openssl-async is out for the same reason: it needs the async API of a
# particular OpenSSL, and the runner's system OpenSSL moves under us.
#
# mod_config and mod_dubbo need no library the runner lacks either, but they go
# to the inventory job rather than here, because mod_dubbo is C++: that job is
# the only place a new compiler's C++ front end gets exercised, and it reports
# instead of failing.

set -e

: "${CC:=gcc}"
export CC

echo "== $CC version =="
$CC --version

./configure \
    --with-cc-opt="$NGX_EXTRA_CC_OPT" \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_auth_request_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_degradation_module \
    --with-http_slice_module \
    --with-http_json_module \
    --with-http_stub_status_module \
    --with-control-api \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_ssl_preread_module \
    --with-stream_sni \
    --add-module=./modules/mod_append_header \
    --add-module=./modules/mod_common \
    --add-module=./modules/mod_strategy \
    --add-module=./modules/ngx_backtrace_module \
    --add-module=./modules/ngx_debug_pool \
    --add-module=./modules/ngx_debug_timer \
    --add-module=./modules/ngx_debug_conn \
    --add-module=./modules/ngx_http_concat_module \
    --add-module=./modules/ngx_http_footer_filter_module \
    --add-module=./modules/ngx_http_proxy_connect_module \
    --add-module=./modules/ngx_http_reqstat_module \
    --add-module=./modules/ngx_http_slice_module \
    --add-module=./modules/ngx_http_sysguard_module \
    --add-module=./modules/ngx_http_trim_filter_module \
    --add-module=./modules/ngx_http_upstream_check_module \
    --add-module=./modules/ngx_http_upstream_consistent_hash_module \
    --add-module=./modules/ngx_http_upstream_dynamic_module \
    --add-module=./modules/ngx_http_upstream_dyups_module \
    --add-module=./modules/ngx_http_upstream_iwrr_module \
    --add-module=./modules/ngx_http_upstream_keepalive_module \
    --add-module=./modules/ngx_http_upstream_session_sticky_module \
    --add-module=./modules/ngx_http_upstream_vnswrr_module \
    --add-module=./modules/ngx_http_user_agent_module \
    --add-module=./modules/ngx_multi_upstream_module \
    --add-module=./modules/ngx_slab_stat \
    --without-http_upstream_keepalive_module \
    "$@"

# configure rewrites the top-level Makefile to point at whichever build
# directory was chosen, so read the build directory back from there instead of
# assuming objs/ -- a leftover objs/Makefile from an earlier local build with
# different flags would otherwise be the thing reported.
ngx_objs=$(sed -n 's|^[[:space:]]*$(MAKE) -f \(.*\)/Makefile$|\1|p' Makefile | head -1)

echo "== CFLAGS as configure assembled them ($ngx_objs) =="
grep -m1 '^CFLAGS' "$ngx_objs/Makefile"
