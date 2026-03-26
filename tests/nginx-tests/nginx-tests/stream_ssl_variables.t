#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module with variables.

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
	->has(qw/stream stream_ssl stream_return socket_ssl_sni/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_session_cache builtin;

    server {
        listen  127.0.0.1:8080;
        listen  127.0.0.1:8443 ssl;
        return  $ssl_session_reused:$ssl_session_id:$ssl_cipher:$ssl_protocol;
    }

    server {
        listen  127.0.0.1:8444 ssl;
        return  $ssl_server_name;
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

$t->run()->plan(6);

###############################################################################

my $s;

is(stream('127.0.0.1:' . port(8080))->read(), ':::', 'no ssl');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8443),
	SSL => 1,
	SSL_session_cache_size => 100
);
like($s->read(), qr/^\.:(\w{64})?:[\w-]+:(TLS|SSL)v(\d|\.)+$/,
	'ssl variables');

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8443),
	SSL => 1,
	SSL_reuse_ctx => $s->socket()
);
like($s->read(), qr/^r:(\w{64})?:[\w-]+:(TLS|SSL)v(\d|\.)+$/,
	'ssl variables - session reused');

}

SKIP: {
skip 'no sni', 3 unless $t->has_module('sni');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8444),
	SSL => 1,
	SSL_session_cache_size => 100,
	SSL_hostname => 'example.com'
);
is($s->read(), 'example.com', 'ssl server name');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8444),
	SSL => 1,
	SSL_reuse_ctx => $s->socket(),
	SSL_hostname => 'example.com'
);
is($s->read(), 'example.com', 'ssl server name - reused');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8444),
	SSL => 1
);
is($s->read(), '', 'ssl server name empty');

}

undef $s;

###############################################################################

sub test_tls13 {
	my $s = stream(PeerAddr => '127.0.0.1:' . port(8443), SSL => 1);
	$s->read() =~ /TLSv1.3/;
}

###############################################################################
