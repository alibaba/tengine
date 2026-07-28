#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for HTTP/3 (xquic) enforcement of the http core max_headers
# directive.
#
# Regression test for the "HTTP/3 Bomb" — the QPACK-on-HTTP/3 analog of
# the HPACK indexed-reference amplification documented at
# https://blog.calif.io/p/codex-discovered-a-hidden-http2-bomb
#
# An attacker sends a request with thousands of header fields.  The
# byte-based large_client_header_buffers limit barely fires because
# each field is small, while the server allocates a full header slot
# per field.  max_headers caps the per-request field count and trips
# the request before the amplification can take hold.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib '../../../tests/nginx-tests/nginx-tests/lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

# Locate xquic test_client.  Without it we can only check that the
# directive is parsed; with it we can drive a real HTTP/3 request and
# observe the server's response to an oversized header set.

my $test_client = $ENV{TEST_XQUIC_CLIENT};
my $has_test_client = 0;

if (!$test_client) {
    foreach my $dir (split(/:/, $ENV{PATH} || '')) {
        if (-x "$dir/test_client") {
            $test_client = "$dir/test_client";
            $has_test_client = 1;
            last;
        }
    }
} else {
    $has_test_client = -x $test_client ? 1 : 0;
}

# Tests: 2 sanity tests (directive parse + xquic startup) always run,
# 4 e2e tests (baseline 200 + bomb rejected, x2 servers) when
# test_client is available — otherwise skipped, but still counted
# in the plan since Test::More's skip() emits "ok # SKIP" lines.

my $t = Test::Nginx->new()->has(qw/http rewrite/)
    ->has_daemon('openssl')
    ->plan(6)
    ->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

xquic_log   logs/xquic.log debug;

http {
    %%TEST_GLOBALS_HTTP%%

    xquic_ssl_certificate        %%TESTDIR%%/localhost.crt;
    xquic_ssl_certificate_key    %%TESTDIR%%/localhost.key;

    # Server A: explicit low cap, easy to trip from a single test_client run.
    server {
        listen 127.0.0.1:%%PORT_8989_UDP%% xquic;
        server_name localhost;

        ssl_certificate        %%TESTDIR%%/localhost.crt;
        ssl_certificate_key    %%TESTDIR%%/localhost.key;

        max_headers 5;

        location / {
            return 200 "HTTP3 OK\n";
        }
    }

    # Server B: default cap (1000), still rejects the test_client's
    # MAX_HEADER-bounded oversize attempt via max_headers 20 — we lower
    # the cap here too because test_client's compile-time MAX_HEADER is
    # 100, so we cannot drive 1000+ fields from a single client run.
    server {
        listen 127.0.0.1:%%PORT_8990_UDP%% xquic;
        server_name localhost;

        ssl_certificate        %%TESTDIR%%/localhost.crt;
        ssl_certificate_key    %%TESTDIR%%/localhost.key;

        max_headers 20;

        location / {
            return 200 "HTTP3 OK\n";
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
    system('openssl req -x509 -new '
        . "-config '$d/openssl.conf' -subj '/CN=$name/' "
        . "-out '$d/$name.crt' -keyout '$d/$name.key' "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', "Test Page\n");

$t->run();

###############################################################################

# Sanity tests — always run.

sleep 1;
my $error_log = $t->read_file('error.log');
unlike($error_log, qr/unknown directive.*max_headers/i,
       'max_headers directive recognized in xquic server block');
unlike($error_log, qr/\[(emerg|alert)\]/,
       'no emerg/alert in error log on startup');

###############################################################################

# End-to-end tests — only when test_client is available.

SKIP: {
    skip 'test_client not available', 4 unless $has_test_client;

    sleep 2;

    # 1) baseline against server A (max_headers 5): -q 6 sends
    # 4 pseudo + 2 user headers; 2 <= 5, request must succeed.
    my $base_a = run_client($test_client, port(8989), 6);
    diag("baseline (server A, -q 6):\n$base_a");
    like($base_a, qr/:status = 200/,
         'server A baseline - :status = 200');

    # 2) bomb against server A: -q 30 sends 4 pseudo + 26 user
    # headers; 26 > 5, request must be rejected.
    my $bomb_a = run_client($test_client, port(8989), 30);
    diag("bomb (server A, -q 30):\n$bomb_a");
    unlike($bomb_a, qr/:status = 200/,
           'server A bomb - request not 200');

    # 3) baseline against server B (max_headers 20): -q 10 sends
    # 4 pseudo + 6 user headers; 6 <= 20, request must succeed.
    my $base_b = run_client($test_client, port(8990), 10);
    diag("baseline (server B, -q 10):\n$base_b");
    like($base_b, qr/:status = 200/,
         'server B baseline - :status = 200');

    # 4) bomb against server B: -q 60 sends 4 pseudo + 56 user
    # headers; 56 > 20, request must be rejected.
    my $bomb_b = run_client($test_client, port(8990), 60);
    diag("bomb (server B, -q 60):\n$bomb_b");
    unlike($bomb_b, qr/:status = 200/,
           'server B bomb - request not 200');
}

# Clear error log so the framework's own no-alerts check doesn't trip
# on the noise test_client and finalize_request(494) generate.
$t->write_file('error.log', '') if $has_test_client;

$t->stop();

###############################################################################

sub run_client {
    my ($client, $port, $q) = @_;
    # -V 1: accept self-signed certs; -t 5: 5s timeout; -l e: error log
    # level; -q N: name-value pair count for the request header block.
    return `$client -a 127.0.0.1 -p $port -u https://localhost/ -h localhost -l e -V 1 -t 5 -q $q 2>&1`;
}

###############################################################################
