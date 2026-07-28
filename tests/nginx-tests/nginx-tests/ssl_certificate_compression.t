#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, certificate compression.

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

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_compression on;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate rsa.crt;

        ssl_certificate_compression off;

        add_header X-Protocol $ssl_protocol;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate rsa.crt;
    }

    server {
        listen       127.0.0.1:8445 ssl;
        server_name  localhost;

        # catch replaced certificates

        ssl_certificate_key repl.key;
        ssl_certificate repl.crt;

        ssl_certificate_key ec.key;
        ssl_certificate ec.crt;

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
system("openssl genrsa -out $d/repl.key 2048 >>$d/openssl.out 2>&1") == 0
	or die "Can't create RSA pem: $!\n";
system("openssl genrsa -out $d/rsa.key 2048 >>$d/openssl.out 2>&1") == 0
	or die "Can't create RSA pem: $!\n";

foreach my $name ('ec', 'repl', 'rsa') {
	system("openssl req -x509 -new -key $d/$name.key "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');

$t->try_run('no ssl_certificate_compression');

plan(skip_all => 'no ssl_certificate_compression support')
	if $t->read_file('error.log') =~ /SSL_CTX_compress_certs/;
plan(skip_all => 'no set_msg_callback, old IO::Socket::SSL')
	if $IO::Socket::SSL::VERSION < 2.081;

$t->plan(8);

###############################################################################

# handshake type:
#
# certificate(11)
# compressed_certificate(25)

my $cert_ht;
my $has_zlib = 0;

like(get('/', 8443), qr/200 OK/, 'request');
is($cert_ht, 11, 'cert compression off');

# only supported with TLS 1.3 and newer

my $exp = 25;
$exp = 11 unless test_tls13();

like(get('/', 8444), qr/200 OK/, 'request 2');

TODO: {
local $TODO = 'not yet'
	if $t->has_module('BoringSSL|AWS-LC') and !$t->has_version('1.29.3');
local $TODO = 'OpenSSL too old'
	unless $t->has_feature('openssl:3.2')
	or $t->has_module('BoringSSL|AWS-LC');

is($cert_ht, $exp, 'cert compression on');

}

SKIP: {
skip 'no multiple certificates', 4 if $t->has_module('BoringSSL');

like(cert('/', 8445, 'RSA'), qr/CN=rsa/, 'request RSA');

TODO: {
local $TODO = 'not yet'
	if $t->has_module('AWS-LC') and !$t->has_version('1.29.3');
local $TODO = 'OpenSSL too old'
	unless $t->has_feature('openssl:3.2')
	or $t->has_module('AWS-LC');

is($cert_ht, $exp, 'cert compression RSA');

}

like(cert('/', 8445, 'ECDSA'), qr/CN=ec/, 'request ECDSA');

TODO: {
local $TODO = 'not yet'
	if $t->has_module('AWS-LC') and !$t->has_version('1.29.3');
local $TODO = 'OpenSSL too old'
	unless $t->has_feature('openssl:3.2')
	or $t->has_module('AWS-LC');

is($cert_ht, $exp, 'cert compression ECDSA');

}
}

###############################################################################

sub test_tls13 {
	http_get('/', SSL => 1) =~ /TLSv1.3/ && $has_zlib;
}

sub get {
	my ($uri, $port) = @_;
	my $s = get_ssl_socket($port) or return;
	http_get($uri, socket => $s);
}

sub cert {
	my ($uri, $port, $type) = @_;
	my $s = get_ssl_socket($port, $type) or return;
	return $s->dump_peer_certificate();
}

sub get_ssl_socket {
	my ($port, $type) = @_;

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

	my $s = http(
		'', PeerAddr => '127.0.0.1:' . port($port), start => 1,
		SSL => 1,
		SSL_startHandshake => 0,
		$type ? (
		SSL_create_ctx_callback => $ctx_cb
		) : ()
	);
	$s->set_msg_callback(\&cb, 0, 0);
	$cert_ht = undef;
	$s->connect_SSL();
	http('', start => 1, socket => $s);
}

sub cb {
	my ($s, $wr, $ssl_ver, $ct, $buf) = @_;

	if ($wr == 1 && $ssl_ver == 0x0304 && $ct == 22) {

		return if $has_zlib;
		return unless unpack("C", $buf) == 1;

		# TLSv1.3 ClientHello

		my $n = 6 + 32;
		my $slen = unpack("C", substr($buf, $n));
		$n += 1 + $slen;
		my $clen = unpack("n", substr($buf, $n));
		$n += 2 + $clen + 2 + 2;

		while ($n < length($buf)) {

			my $ext = unpack("n", substr($buf, $n));
			my $len = unpack("n", substr($buf, $n + 2));

			if ($ext != 27) {
				$n += 4 + $len;
				next;
			}

			# compress_certificate(27)

			$n += 4;
			for (my $k = 1; $k < $len; $k += 2) {
				my $algo = unpack("n", substr($buf, $n + $k));
				$has_zlib = 1 if $algo == 1;
				last;
			}

			last;
		}
	}

	if ($wr == 0 && $ct == 22) {

		my $ht = unpack("C", $buf);
		return unless $ht == 11 || $ht == 25;

		log_in("ssl cert handshake type: " . $ht);
		$cert_ht = $ht;
	}
}

###############################################################################
