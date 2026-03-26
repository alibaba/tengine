#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with ssl and http proxy cache.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl http_v2 proxy cache socket_ssl_alpn/)
	->has_daemon('openssl');

plan(skip_all => 'no ALPN support in OpenSSL')
	if $t->has_module('OpenSSL') and not $t->has_feature('openssl:1.0.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8443 ssl sndbuf=32k;
        server_name  localhost;

        http2 on;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        send_timeout 1s;
        lingering_close off;

        location / {
            proxy_pass   http://127.0.0.1:8081;
            proxy_cache  NAME;
        }
    }

    server {
        listen       127.0.0.1:8081 sndbuf=64k;
        server_name  localhost;

        location / { }
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
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 500000)));

$t->run()->plan(1);

###############################################################################

# client cancels stream with a cacheable request sent to upstream causing alert

my $s = getconn();
ok($s, 'ssl connection');

my $sid = $s->new_stream();
$s->h2_rst($sid, 8);

# large response may stuck in SSL buffer and won't be sent producing alert

my $s2 = getconn();
$sid = $s2->new_stream({ path => '/tbig.html' });
$s2->h2_window(2**30, $sid);
$s2->h2_window(2**30);

select undef, undef, undef, 0.2;

$t->stop();

###############################################################################

sub getconn {
	my $sock = http('', start => 1, SSL => 1, SSL_alpn_protocols => ['h2']);
	Test::Nginx::HTTP2->new(undef, socket => $sock);
}

###############################################################################
