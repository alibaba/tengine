#!/bin/sh
#
# Smoke-tests a Tengine container image: the binary runs, the configuration
# parses, HTTP works, and the three bundled subsystems (Tongsuo/NTLS, xquic,
# Lua) are really in the build rather than just claimed in the release notes.
#
#     .github/scripts/verify-image.sh ghcr.io/alibaba/tengine:3.2.0
#     .github/scripts/verify-image.sh ghcr.io/alibaba/tengine:3.2.0-perl --variant perl
#
# With --variant perl the perl module is additionally required to load and run
# a handler; without it, the module is required to be ABSENT, which is what
# keeps the default image from quietly growing the variant's payload.
#
# Used by .github/workflows/docker.yml for both the build-only and the
# published-tag verification paths.
#

set -eu

IMAGE=""
VARIANT=default
while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT=$2; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *)  [ -z "$IMAGE" ] || { echo "unexpected argument: $1" >&2; exit 2; }
            IMAGE=$1; shift ;;
    esac
done
[ -n "$IMAGE" ] || {
    echo "usage: ${0##*/} <image ref> [--variant perl]" >&2
    exit 2
}

ok()   { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# CMD is overridden, there is no ENTRYPOINT to work around.
in_image() { docker run --rm "$IMAGE" "$@"; }

echo "verifying $IMAGE (variant: $VARIANT)"

PERL_MODULE=/usr/lib/tengine/modules/ngx_http_perl_module.so

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

# ---------------------------------------------------------------- perl payload

# One compile feeds both variants, so the banner always advertises the perl
# module and cannot distinguish them -- only the presence of the .so can. The
# negative check matters just as much as the positive one: if the builder ever
# stops moving the module into /out-perl, the default image would silently ship
# it (and fail to load it, having no libperl).
if in_image test -f "$PERL_MODULE" 2>/dev/null; then
    have_perl=yes
else
    have_perl=no
fi

case "$VARIANT:$have_perl" in
    perl:yes)    ok "ngx_http_perl_module.so is present" ;;
    perl:no)     fail "the perl variant is missing $PERL_MODULE" ;;
    default:no)  ok "no perl module in the default image, as intended" ;;
    default:yes) fail "$PERL_MODULE leaked into the default image" ;;
esac

# ------------------------------------------------------------------ config test

in_image /usr/sbin/tengine -t >/dev/null 2>&1 || fail "tengine -t failed"
ok "tengine -t passes"

# ------------------------------------------------------------------- http + lua

# resty.core is required by ngx_http_lua_module at startup, and cjson is a
# compiled C module, so this one request exercises both lua_package_path and
# lua_package_cpath -- the two settings most likely to be wrong in a package.
# The same request also names the regex engine: ngx_http_lua_module only gained
# PCRE2 support in 0.10.26, and the distro packages all build against PCRE2, so
# a downgrade of either would break the build again without this check.
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
            -- An invalid pattern makes the regex engine name itself in the
            -- error string: pcre2_compile() on PCRE2, pcre_compile() on PCRE1.
            local _, re_err = ngx.re.match("x", "(")
            ngx.say(cjson.encode({
                lua = "ok",
                jit = jit and jit.version or "none",
                regex = re_err or "no error",
            }))
        }
    }
}
EOF

# A second server block rather than another location, so the Lua one above
# stays byte-identical between the two variants.
#
# require nginx + $nginx::VERSION is the point of the handler: nginx.pm lives in
# the private perl_modules_path compiled into the binary's @INC, so a response
# carrying its version proves that path resolved. Returning 0 (NGX_OK) instead
# of the OK constant keeps the handler independent of nginx.pm's exports.
perl_ports=""
if [ "$VARIANT" = perl ]; then
    perl_ports="-p 18082:8082"
    cat >> "$workdir/zz-verify.conf" <<'EOF'

server {
    listen 8082;

    location = /verify-perl {
        perl 'sub {
            my $r = shift;
            require nginx;
            $r->send_http_header("text/plain");
            $r->print("perl:ok nginx.pm=" . $nginx::VERSION . "\n");
            return 0;
        }';
    }
}
EOF
fi

# $perl_ports is deliberately unquoted: it is either empty or two words.
# shellcheck disable=SC2086
cid=$(docker run -d -p 18080:80 -p 18081:8081 $perl_ports \
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
case "$lua_out" in
    *pcre2_compile*) ok "Lua regexes run on PCRE2" ;;
    *)               fail "Lua regexes are not on PCRE2: $lua_out" ;;
esac

# ------------------------------------------------------------------------ perl

if [ "$VARIANT" = perl ]; then
    perl_out=$(curl -fsS "http://127.0.0.1:18082/verify-perl") || {
        docker logs "$cid" || true
        fail "the perl endpoint did not respond"
    }
    case "$perl_out" in
        *'perl:ok'*) ok "perl handler runs: $perl_out" ;;
        *)           fail "unexpected perl output: $perl_out" ;;
    esac
    # An unresolved nginx.pm would have made `require nginx` die before this.
    case "$perl_out" in
        *nginx.pm=[0-9]*) ok "nginx.pm resolved from the compiled-in @INC" ;;
        *)                fail "nginx.pm did not report a version: $perl_out" ;;
    esac
fi

echo "all checks passed for $IMAGE (variant: $VARIANT)"
