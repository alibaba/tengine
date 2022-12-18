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

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
};
plan(skip_all => 'Net::SSLeay not installed') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
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
        listen  127.0.0.1:8081 ssl;
        return  $ssl_session_reused:$ssl_session_id:$ssl_cipher:$ssl_protocol;
    }

    server {
        listen  127.0.0.1:8082 ssl;
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

my ($s, $ssl);

is(stream('127.0.0.1:' . port(8080))->read(), ':::', 'no ssl');

($s, $ssl) = get_ssl_socket(port(8081));
like(Net::SSLeay::read($ssl), qr/^\.:(\w{64})?:[\w-]+:(TLS|SSL)v(\d|\.)+$/,
	'ssl variables');

my $ses = Net::SSLeay::get_session($ssl);
($s, $ssl) = get_ssl_socket(port(8081), $ses);
like(Net::SSLeay::read($ssl), qr/^r:\w{64}:[\w-]+:(TLS|SSL)v(\d|\.)+$/,
	'ssl variables - session reused');

SKIP: {
skip 'no sni', 3 unless $t->has_module('sni');

($s, $ssl) = get_ssl_socket(port(8082), undef, 'example.com');
is(Net::SSLeay::ssl_read_all($ssl), 'example.com', 'ssl server name');

my $ses = Net::SSLeay::get_session($ssl);
($s, $ssl) = get_ssl_socket(port(8082), $ses, 'example.com');
is(Net::SSLeay::ssl_read_all($ssl), 'example.com', 'ssl server name - reused');

($s, $ssl) = get_ssl_socket(port(8082));
is(Net::SSLeay::ssl_read_all($ssl), '', 'ssl server name empty');

}

###############################################################################

sub get_ssl_socket {
	my ($port, $ses, $name) = @_;

	my $s = IO::Socket::INET->new('127.0.0.1:' . $port);
	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_tlsext_host_name($ssl, $name) if defined $name;
	Net::SSLeay::set_session($ssl, $ses) if defined $ses;
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
}

###############################################################################
