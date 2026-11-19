#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module with multiple certificates.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl/)
	->has_daemon('openssl');

plan(skip_all => 'no multiple certificates') if $t->has_module('BoringSSL');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key rsa.key;
    ssl_certificate rsa.crt;
    ssl_ciphers DEFAULT:ECCdraft;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate_key ec.key;
        ssl_certificate ec.crt;

        ssl_certificate_key rsa.key;
        ssl_certificate rsa.crt;

        ssl_certificate_key rsa.key;
        ssl_certificate rsa.crt;
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

system("openssl ecparam -genkey -out $d/ec.key -name prime256v1 "
	. ">>$d/openssl.out 2>&1") == 0 or die "Can't create EC pem: $!\n";
system("openssl genrsa -out $d/rsa.key 2048 >>$d/openssl.out 2>&1") == 0
	or die "Can't create RSA pem: $!\n";

foreach my $name ('ec', 'rsa') {
	system("openssl req -x509 -new -key $d/$name.key "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run()->plan(2);

###############################################################################

like(cert('RSA'), qr/CN=rsa/, 'ssl cert RSA');
like(cert('ECDSA'), qr/CN=ec/, 'ssl cert ECDSA');

###############################################################################

sub cert {
	my $s = get_socket(@_) || return;
	return $s->dump_peer_certificate();
}

sub get_socket {
	my ($type) = @_;

	my $ctx_cb = sub {
		my $ctx = shift;
		return unless defined $type;
		my $ssleay = Net::SSLeay::SSLeay();
		return if ($ssleay < 0x1000200f || $ssleay == 0x20000000);
		my @sigalgs = ('RSA+SHA256:PSS+SHA256', 'RSA+SHA256');
		@sigalgs = ($type . '+SHA256') unless $type eq 'RSA';
		# SSL_CTRL_SET_SIGALGS_LIST
		Net::SSLeay::CTX_ctrl($ctx, 98, 0, $sigalgs[0])
			or Net::SSLeay::CTX_ctrl($ctx, 98, 0, $sigalgs[1])
			or die("Failed to set sigalgs");
	};

	return http(
		'', start => 1,
		SSL => 1,
		SSL_cipher_list => $type,
		SSL_create_ctx_callback => $ctx_cb
	);
}

###############################################################################
