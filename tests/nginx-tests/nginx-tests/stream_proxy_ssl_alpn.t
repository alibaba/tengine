#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for proxy_ssl_alpn directive in stream proxy.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl stream_return socket_ssl_alpn/)
	->has_daemon('openssl');

plan(skip_all => 'no ALPN support in OpenSSL')
	if $t->has_module('OpenSSL') and not $t->has_feature('openssl:1.0.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_ssl on;

    ssl_certificate_key localhost.key;
    ssl_certificate     localhost.crt;

    server {
        listen      127.0.0.1:8443 ssl;
        ssl_alpn    v1;

        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8444 ssl;

        proxy_pass      127.0.0.1:8090;
        proxy_ssl_alpn  v2;
    }

    server {
        listen      127.0.0.1:8445 ssl;
        ssl_alpn    v1 v2;

        proxy_pass      127.0.0.1:8090;
        proxy_ssl_alpn  $ssl_alpn_protocol;
    }

    server {
        listen      127.0.0.1:8446 ssl;
        ssl_alpn    v1 v2;

        proxy_pass      127.0.0.1:8090;
        proxy_ssl_alpn  $ssl_alpn_protocol v2;
    }

    server {
        listen      127.0.0.1:8090 ssl;
        ssl_alpn    v1 v2;
        return      $ssl_alpn_protocol;
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

$t->try_run('no proxy_ssl_alpn')->plan(6);

###############################################################################

is(get(8443, [ 'v1' ]), '', 'empty not sent');
is(get(8444), 'v2', 'literal value');
is(get(8445, [ 'v1' ]), 'v1', 'variable');
is(get(8445), '', 'variable empty');

is(get(8446, [ 'v1' ]), 'v1', 'many 1');
is(get(8446), 'v2', 'many 2');

###############################################################################

sub get {
	my ($port, $alpn) = @_;

	my $s = stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		(defined $alpn ? (SSL_alpn_protocols => $alpn) : ()),
	);

	return $s->read();
}

###############################################################################
