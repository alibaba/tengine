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

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
	Net::SSLeay::SSLeay();
};
plan(skip_all => 'Net::SSLeay not installed or too old') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->has_daemon('openssl');

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
        listen       127.0.0.1:8080 ssl;
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

like(get_cert('RSA'), qr/CN=rsa/, 'ssl cert RSA');
like(get_cert('ECDSA'), qr/CN=ec/, 'ssl cert ECDSA');

###############################################################################

sub get_version {
	my ($s, $ssl) = get_ssl_socket();
	return Net::SSLeay::version($ssl);
}

sub get_cert {
	my ($type) = @_;
	$type = 'PSS' if $type eq 'RSA' && get_version() > 0x0303;
	my ($s, $ssl) = get_ssl_socket($type);
	my $cipher = Net::SSLeay::get_cipher($ssl);
	Test::Nginx::log_core('||', "cipher: $cipher");
	return Net::SSLeay::dump_peer_certificate($ssl);
}

sub get_ssl_socket {
	my ($type) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::INET->new('127.0.0.1:' . port(8080));
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");

	if (defined $type) {
		my $ssleay = Net::SSLeay::SSLeay();
		if ($ssleay < 0x1000200f || $ssleay == 0x20000000) {
			Net::SSLeay::CTX_set_cipher_list($ctx, $type)
				or die("Failed to set cipher list");
		} else {
			# SSL_CTRL_SET_SIGALGS_LIST
			Net::SSLeay::CTX_ctrl($ctx, 98, 0, $type . '+SHA256')
				or die("Failed to set sigalgs");
		}
	}

	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
}

###############################################################################
