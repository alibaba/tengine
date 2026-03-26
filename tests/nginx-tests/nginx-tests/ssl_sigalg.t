#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, $ssl_sigalg and $ssl_client_sigalg variables.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl openssl:3.5 socket_ssl/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate_key ec.key;
        ssl_certificate ec.crt;

        ssl_certificate_key rsa.key;
        ssl_certificate rsa.crt;

        ssl_verify_client optional;
        ssl_client_certificate bundle.crt;

        add_header X-SigAlg $ssl_sigalg:$ssl_client_sigalg;
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

$t->write_file('bundle.crt', $t->read_file('ec.crt') .
	$t->read_file('rsa.crt'));

$t->write_file('index.html', '');

$t->try_run('no ssl_sigalg')->plan(6);

###############################################################################

like(cert('RSA'), qr/CN=rsa/, 'ssl cert RSA');
like(cert('ECDSA'), qr/CN=ec/, 'ssl cert ECDSA');

like(get('RSA'), qr/rsa_(pss_rsae|pkcs1)_sha256/, 'ssl sigalg RSA');
like(get('ECDSA'), qr/ecdsa_secp256r1_sha256/, 'ssl sigalg ECDSA');

like(get('RSA', 'rsa'), qr/:rsa_pss_rsae_sha256/, 'ssl client sigalg PSS');
like(get('RSA', 'ec'), qr/:ecdsa_secp256r1_sha256/, 'ssl client sigalg ECDSA');

###############################################################################

sub cert {
	my $s = get_socket(@_) || return;
	return $s->dump_peer_certificate();
}

sub get {
	my $s = get_socket(@_) || return;
	http_get('/', socket => $s);
}

sub get_socket {
	my ($type, $cert) = @_;

	my $ctx_cb = sub {
		my $ctx = shift;
		return unless defined $type;
		my $ssleay = Net::SSLeay::SSLeay();
		return if ($ssleay < 0x1000200f || $ssleay == 0x20000000);
		my $rsa = ('RSA+SHA256:PSS+SHA256');
		my $ecdsa = ('ECDSA+SHA256');
		my $sigalgs = $type eq 'RSA' ? "$rsa:$ecdsa" : "$ecdsa:$rsa";
		# SSL_CTRL_SET_SIGALGS_LIST
		Net::SSLeay::CTX_ctrl($ctx, 98, 0, $sigalgs)
			or die("Failed to set sigalgs");
	};

	return http(
		'', start => 1,
		SSL => 1,
		SSL_cipher_list => $type,
		SSL_create_ctx_callback => $ctx_cb,
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : (),
	);
}

###############################################################################
