#!/bin/sh
#
# Smoke-tests a Tengine container image: the binary runs, the configuration
# parses, HTTP works, and the three bundled subsystems (Tongsuo/NTLS, xquic,
# Lua) are really in the build rather than just claimed in the release notes.
#
#     .github/scripts/verify-image.sh ghcr.io/alibaba/tengine:3.2.0
#
# Used by .github/workflows/docker.yml for both the build-only and the
# published-tag verification paths.
#

set -eu

[ $# -eq 1 ] || { echo "usage: ${0##*/} <image ref>" >&2; exit 2; }
IMAGE=$1

ok()   { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# CMD is overridden, there is no ENTRYPOINT to work around.
in_image() { docker run --rm "$IMAGE" "$@"; }

echo "verifying $IMAGE"

# ---------------------------------------------------------------- build config

# `tengine -V` only succeeds if the dynamic linker resolved every bundled
# library, which is the real test of the rpath baked in for libxquic.so and
# libluajit.
banner=$(in_image /usr/sbin/tengine -V 2>&1) || fail "tengine -V did not run"
printf '%s\n' "$banner" | sed 's/^/    /'

for mod in ngx_tongsuo_ntls ngx_http_xquic_module ngx_http_lua_module; do
    case "$banner" in
        *"$mod"*) ok "$mod compiled in" ;;
        *)        fail "$mod missing from configure arguments" ;;
    esac
done

# Tongsuo reports itself through OPENSSL_VERSION_TEXT ("OpenSSL 3.0.3 ...") and
# nginx never prints TONGSUO_VERSION_TEXT, so the banner alone cannot tell it
# apart from a stock OpenSSL. The configure arguments can: enable-ntls is a
# Tongsuo-only option and is what ngx_tongsuo_ntls actually needs.
case "$banner" in
    *enable-ntls*) ok "built against Tongsuo with NTLS enabled" ;;
    *) fail "no enable-ntls in the configure arguments: NTLS is not really in this build" ;;
esac

# ------------------------------------------------------------------ config test

in_image /usr/sbin/tengine -t >/dev/null 2>&1 || fail "tengine -t failed"
ok "tengine -t passes"

# ------------------------------------------------------------------- http + lua

# resty.core is required by ngx_http_lua_module at startup, and cjson is a
# compiled C module, so this one request exercises both lua_package_path and
# lua_package_cpath -- the two settings most likely to be wrong in a package.
workdir=$(mktemp -d)
cid=""
# ${cid:-} because the trap can fire before the container is started.
trap 'rm -rf "$workdir"; [ -n "${cid:-}" ] && docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
cat > "$workdir/zz-verify.conf" <<'EOF'
server {
    listen 8081;

    location = /verify-lua {
        default_type text/plain;
        content_by_lua_block {
            require "resty.core"
            local cjson = require "cjson"
            ngx.say(cjson.encode({ lua = "ok", jit = jit and jit.version or "none" }))
        }
    }
}
EOF

cid=$(docker run -d -p 18080:80 -p 18081:8081 \
    -v "$workdir/zz-verify.conf:/etc/tengine/conf.d/zz-verify.conf:ro" \
    "$IMAGE")

# The server is up within a second in practice; retry rather than sleep blindly.
i=0
while [ "$i" -lt 30 ]; do
    if curl -fsS -o /dev/null "http://127.0.0.1:18080/" 2>/dev/null; then
        break
    fi
    i=$((i + 1))
    sleep 1
done
[ "$i" -lt 30 ] || { docker logs "$cid" || true; fail "no HTTP response on port 80"; }
ok "serves HTTP on port 80"

lua_out=$(curl -fsS "http://127.0.0.1:18081/verify-lua") || {
    docker logs "$cid" || true
    fail "the Lua endpoint did not respond"
}
case "$lua_out" in
    *'"lua":"ok"'*) ok "Lua runs: $lua_out" ;;
    *)              fail "unexpected Lua output: $lua_out" ;;
esac
case "$lua_out" in
    *LuaJIT*) ok "LuaJIT is the Lua VM" ;;
    *)        fail "not running on LuaJIT: $lua_out" ;;
esac

echo "all checks passed for $IMAGE"
