#!/usr/bin/perl

# Tests for rewrite module: heap buffer overflow with overlapping captures.
# Regression test for CVE-2026-9256.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # PoC #1: redirect with overlapping captures.
        # Before the fix, a long '+' sequence in the URI caused
        # heap-buffer-overflow because the allocated length only counted
        # one escape pass while $1 and $2 each escaped the same data.
        location /redirect/ {
            rewrite ^/redirect/((.*))$ http://example.com/$1$2 redirect;
            return 200 unreached;
        }

        # PoC #2: in-place rewrite with args and overlapping captures.
        # The replacement contains '?' which triggers the plus_in_uri
        # escape path without redirect.
        location /args/ {
            rewrite ^/args/((.*))$ /target?$1$2;
            return 200 unreached;
        }

        location /target {
            return 200 "args=$args";
        }

        # Regression: simple non-overlapping capture must still work.
        location /simple/ {
            rewrite ^/simple/(.*)$ http://example.com/$1 redirect;
            return 200 unreached;
        }

        # is_args leakage check: a prior rewrite must not leave is_args=1
        # which would corrupt length calculation of a later set/if.
        location /leak/ {
            rewrite ^ /next?a=1 last;
        }

        location /next {
            set $tmp "x=$arg_a";
            return 200 "tmp=$tmp";
        }
    }
}

EOF

$t->run();

###############################################################################

# PoC #1 - long '+' run forces large escape expansion in both $1 and $2.
# Pre-fix: heap-buffer-overflow under ASan / segfault.
my $payload = '+' x 64;
like(http_get("/redirect/$payload"),
    qr{^Location: http://example\.com/}m,
    'overlap captures + redirect (no overflow)');

# PoC #2 - same payload via '?' args path.
# The CVE concern is heap overflow / crash. Pre-fix, the worker would
# segfault and the connection would be reset (http_get returns ''/undef).
# Post-fix, the server simply returns a well-formed HTTP response - any
# status code is acceptable, what matters is that the response exists.
my $r2 = http_get("/args/$payload") || '';
diag("PoC #2 response head: ", substr($r2, 0, 200)) if length($r2) < 20;
ok(length($r2) > 0 && $r2 =~ m{^HTTP/1\.\d \d{3}},
    'overlap captures + args (no crash)');

# Quoted URI variant - '%' triggers quoted_uri branch.
like(http_get('/redirect/%2B%2B%2B%2B%2B%2B%2B%2B'),
    qr{^Location: http://example\.com/}m,
    'overlap captures with %-encoded input');

# Regression: single capture still produces correct Location.
like(http_get('/simple/foo+bar'),
    qr{^Location: http://example\.com/foo(?:%2B|\+)bar}m,
    'non-overlapping capture still works');

# is_args reset hardening (paired with CVE-2026-42945 fix).
like(http_get('/leak/'), qr{tmp=x=1}, 'is_args reset between rewrites');

# Memory safety: worker is alive after the PoC requests above.
like(http_get('/simple/healthcheck'),
    qr{^Location: http://example\.com/healthcheck}m,
    'worker still alive after PoC requests');

###############################################################################
