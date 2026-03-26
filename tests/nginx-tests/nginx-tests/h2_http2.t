#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol, http2 directive.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl http_v2 socket_ssl_alpn/)
	->has_daemon('openssl')->plan(11);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  default;

        http2 on;
    }

    server {
        listen       127.0.0.1:8443;
        server_name  http2;

        http2 on;
    }

    server {
        listen       127.0.0.1:8443;
        server_name  disabled;

        http2 off;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  default;
    }

    server {
        listen       127.0.0.1:8444;
        server_name  http2;

        http2 on;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;
    }

    server {
        listen       127.0.0.1:8081 http2;
        server_name  localhost;
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

$t->write_file('index.html', '');

# suppress deprecation warning

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

###############################################################################

# make sure HTTP/2 can be disabled selectively on virtual servers

ok(get_ssl_socket(8443), 'default to enabled');

TODO: {
local $TODO = 'broken ALPN/SNI order in LibreSSL'
	if $t->has_module('LibreSSL');
local $TODO = 'OpenSSL too old'
	if $t->has_module('OpenSSL')
	and not $t->has_feature('openssl:1.1.0');

ok(!get_ssl_socket(8443, 'disabled'), 'sni to disabled');

}

TODO: {
local $TODO = 'OpenSSL too old'
	if $t->has_module('OpenSSL')
	and not $t->has_feature('openssl:1.0.2');

is(get_https(8443, 'http2'), 200, 'host to enabled');
is(get_https(8443, 'disabled', 'http2'), 421, 'host to disabled');

}

# make sure HTTP/2 can be enabled selectively on virtual servers

TODO: {
local $TODO = 'OpenSSL too old'
	if $t->has_module('OpenSSL')
	and not $t->has_feature('openssl:1.1.0');

ok(!get_ssl_socket(8444), 'default to disabled');

}

TODO: {
local $TODO = 'broken ALPN/SNI order in LibreSSL'
	if $t->has_module('LibreSSL');
local $TODO = 'broken ALPN/SNI order in OpenSSL before 1.0.2h'
	if $t->has_module('OpenSSL')
	and not $t->has_feature('openssl:1.0.2h');

is(get_https(8444, 'http2'), 200, 'sni to enabled');

}

# http2 detection on plain tcp socket by connection preface

like(http_get('/'), qr/200 OK/, 'non-ssl http');
is(get_http(8080), 200, 'non-ssl http2');

like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8081))),
	qr/200 OK/, 'non-ssl http deprecated');
is(get_http(8081), 200, 'non-ssl http2 deprecated');

my $sock = http("PRI * HTTP/2.0\r\n\r\n", start => 1);
select undef, undef, undef, 0.2;
is(get_http(8080, 'localhost', $sock, "SM\r\n\r\n"), 200,
	'preface with multiple packets');

###############################################################################

sub get_http {
	my ($port, $host, $sock, $preface) = @_;
	my $s = Test::Nginx::HTTP2->new(port($port),
		socket => $sock, preface => $preface);
	my $sid = $s->new_stream({ host => $host });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{':status'};
}

sub get_https {
	my ($port, $host, $sni, $alpn) = @_;
	my $sock = get_ssl_socket($port, $sni || $host, $alpn);
	return get_http($port, $host, $sock);
}

sub get_ssl_socket {
	my ($port, $sni, $alpn) = @_;
	return http('', PeerAddr => '127.0.0.1:' . port($port), start => 1,
		SSL => 1,
		SSL_hostname => $sni,
		SSL_alpn_protocols => $alpn || ['h2']);
}

###############################################################################
