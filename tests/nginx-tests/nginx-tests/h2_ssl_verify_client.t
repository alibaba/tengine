#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with ssl, ssl_verify_client.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl sni http_v2 socket_ssl_alpn/)
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

    http2 on;

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    ssl_verify_client optional_no_ca;

    add_header X-Verify $ssl_client_verify;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_client_certificate client.crt;

        location / { }
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  example.com;

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

foreach my $name ('localhost', 'client') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('t', 'SEE-THIS');
$t->run()->plan(3);

###############################################################################

is(get('localhost')->{'x-verify'}, 'SUCCESS', 'success');
like(get('example.com')->{'x-verify'}, qr/FAILED/, 'failed');
is(get('localhost', 'example.com')->{':status'}, '421', 'misdirected');

###############################################################################

sub get_ssl_socket {
	my ($sni) = @_;
	http('', start => 1,
		SSL => 1,
		SSL_alpn_protocols => [ 'h2' ],
		SSL_hostname => $sni,
		SSL_cert_file => "$d/client.crt",
		SSL_key_file => "$d/client.key");
}

sub get {
	my ($sni, $host) = @_;

	$host = $sni if !defined $host;

	my $s = get_ssl_socket($sni);
	my $sess = Test::Nginx::HTTP2->new(port(8080), socket => $s);
	my $sid = $sess->new_stream({ headers => [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/t', mode => 1 },
		{ name => ':authority', value => $host, mode => 1 }]});
	my $frames = $sess->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{'headers'};
}

###############################################################################
