#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for OCSP with client certificates.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64 qw/ decode_base64 /;

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
	defined &Net::SSLeay::set_tlsext_status_type or die;
};
plan(skip_all => 'Net::SSLeay not installed or too old') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni/)->has_daemon('openssl');

plan(skip_all => 'no OCSP stapling') if $t->has_module('BoringSSL');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_ocsp leaf;
    ssl_verify_client on;
    ssl_verify_depth 2;
    ssl_client_certificate trusted.crt;

    ssl_ciphers DEFAULT:ECCdraft;

    ssl_certificate_key ec.key;
    ssl_certificate ec.crt;

    ssl_certificate_key rsa.key;
    ssl_certificate rsa.crt;

    ssl_session_cache shared:SSL:1m;
    ssl_session_tickets off;

    add_header X-Verify x${ssl_client_verify}:${ssl_session_reused}x always;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  sni;

        ssl_ocsp_responder http://127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  resolver;

        ssl_ocsp on;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_ocsp_responder http://127.0.0.1:8081;
        ssl_ocsp on;
    }

    server {
        listen       127.0.0.1:8445 ssl;
        server_name  localhost;

        ssl_ocsp_responder http://127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8446 ssl;
        server_name  localhost;

        ssl_ocsp_cache shared:OCSP:1m;
    }

    server {
        listen       127.0.0.1:8447 ssl;
        server_name  localhost;

        ssl_ocsp_responder http://127.0.0.1:8082;
        ssl_client_certificate root.crt;
    }
}

EOF

my $d = $t->testdir();
my $p = port(8081);

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

$t->write_file('ca.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha256
policy = myca_policy
serial = $d/certserial
default_days = 1
x509_extensions = myca_extensions

[ myca_policy ]
commonName = supplied

[ myca_extensions ]
basicConstraints = critical,CA:TRUE
authorityInfoAccess = OCSP;URI:http://127.0.0.1:$p
EOF

# variant for int.crt to trigger missing resolver

$t->write_file('ca2.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha256
policy = myca_policy
serial = $d/certserial
default_days = 1
x509_extensions = myca_extensions

[ myca_policy ]
commonName = supplied

[ myca_extensions ]
basicConstraints = critical,CA:TRUE
authorityInfoAccess = OCSP;URI:http://localhost:$p
EOF

foreach my $name ('root') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('int', 'end') {
	system("openssl req -new "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('ec-end') {
	system("openssl ecparam -genkey -out $d/$name.key -name prime256v1 "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create EC param: $!\n";
	system("openssl req -new -key $d/$name.key "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

system("openssl ca -batch -config $d/ca2.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-subj /CN=int/ -in $d/int.csr -out $d/int.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for int: $!\n";

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/int.key -cert $d/int.crt "
	. "-subj /CN=ec-end/ -in $d/ec-end.csr -out $d/ec-end.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for ec-end: $!\n";

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/int.key -cert $d/int.crt "
	. "-subj /CN=end/ -in $d/end.csr -out $d/end.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for end: $!\n";

# RFC 6960, serialNumber

system("openssl x509 -in $d/int.crt -serial -noout "
	. ">>$d/serial_int 2>>$d/openssl.out") == 0
	or die "Can't obtain serial for end: $!\n";

my $serial_int = pack("n2", 0x0202, hex $1)
	if $t->read_file('serial_int') =~ /(\d+)/;

system("openssl x509 -in $d/end.crt -serial -noout "
	. ">>$d/serial 2>>$d/openssl.out") == 0
	or die "Can't obtain serial for end: $!\n";

my $serial = pack("n2", 0x0202, hex $1) if $t->read_file('serial') =~ /(\d+)/;

# ocsp end

system("openssl ocsp -issuer $d/int.crt -cert $d/end.crt "
	. "-reqout $d/req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/int.crt -rkey $d/int.key "
	. "-reqin $d/req.der -respout $d/resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP response: $!\n";

system("openssl ocsp -issuer $d/int.crt -cert $d/ec-end.crt "
	. "-reqout $d/ec-req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create EC OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/root.crt -rkey $d/root.key "
	. "-reqin $d/ec-req.der -respout $d/ec-resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create EC OCSP response: $!\n";

$t->write_file('trusted.crt',
	$t->read_file('int.crt') . $t->read_file('root.crt'));

# server cert/key

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

$t->run_daemon(\&http_daemon, $t, port(8081));
$t->run_daemon(\&http_daemon, $t, port(8082));
$t->run()->plan(14);

$t->waitforsocket("127.0.0.1:" . port(8081));
$t->waitforsocket("127.0.0.1:" . port(8082));

my $version = get_version();

###############################################################################

like(get('RSA', 'end'), qr/200 OK.*SUCCESS/s, 'ocsp leaf');

# demonstrate that ocsp int request is failed due to missing resolver

like(get('RSA', 'end', sni => 'resolver'),
	qr/400 Bad.*FAILED:certificate status request failed/s,
	'ocsp many failed request');

# demonstrate that ocsp int request is actually made by failing ocsp response

like(get('RSA', 'end', port => 8444),
	qr/400 Bad.*FAILED:certificate status request failed/s,
	'ocsp many failed');

# now prepare valid ocsp int response

system("openssl ocsp -issuer $d/root.crt -cert $d/int.crt "
	. "-reqout $d/int-req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/root.crt "
	. "-rsigner $d/root.crt -rkey $d/root.key "
	. "-reqin $d/int-req.der -respout $d/int-resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP response: $!\n";

like(get('RSA', 'end', port => 8444), qr/200 OK.*SUCCESS/s, 'ocsp many');

# store into ssl_ocsp_cache

like(get('RSA', 'end', port => 8446), qr/200 OK.*SUCCESS/s, 'cache store');

# revoke

system("openssl ca -config $d/ca.conf -revoke $d/end.crt "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't revoke end.crt: $!\n";

system("openssl ocsp -issuer $d/int.crt -cert $d/end.crt "
	. "-reqout $d/req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/int.crt -rkey $d/int.key "
	. "-reqin $d/req.der -respout $d/revoked.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP response: $!\n";

like(get('RSA', 'end'), qr/400 Bad.*FAILED:certificate revoked/s, 'revoked');

# with different responder where it's still valid

like(get('RSA', 'end', port => 8445), qr/200 OK.*SUCCESS/s, 'ocsp responder');

# with different context to responder where it's still valid

like(get('RSA', 'end', sni => 'sni'), qr/200 OK.*SUCCESS/s, 'ocsp context');

# with cached ocsp response it's still valid

like(get('RSA', 'end', port => 8446), qr/200 OK.*SUCCESS/s, 'cache lookup');

# ocsp end response signed with invalid (root) cert, expect HTTP 400

like(get('ECDSA', 'ec-end'),
	qr/400 Bad.*FAILED:certificate status request failed/s,
	'root ca not trusted');

# now sign ocsp end response with valid int cert

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/int.crt -rkey $d/int.key "
	. "-reqin $d/ec-req.der -respout $d/ec-resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create EC OCSP response: $!\n";

like(get('ECDSA', 'ec-end'), qr/200 OK.*SUCCESS/s, 'ocsp ecdsa');

my ($s, $ssl) = get('ECDSA', 'ec-end');
my $ses = Net::SSLeay::get_session($ssl);

like(get('ECDSA', 'ec-end', ses => $ses),
	qr/200 OK.*SUCCESS:r/s, 'session reused');

# revoke with saved session

system("openssl ca -config $d/ca.conf -revoke $d/ec-end.crt "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't revoke end.crt: $!\n";

system("openssl ocsp -issuer $d/int.crt -cert $d/ec-end.crt "
	. "-reqout $d/ec-req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/int.crt -rkey $d/int.key "
	. "-reqin $d/ec-req.der -respout $d/ec-resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP response: $!\n";

# reusing session with revoked certificate

like(get('ECDSA', 'ec-end', ses => $ses),
	qr/400 Bad.*FAILED:certificate revoked:r/s, 'session reused - revoked');

# regression test for self-signed

like(get('RSA', 'root', port => 8447), qr/200 OK.*SUCCESS/s, 'ocsp one');

###############################################################################

sub get {
	my ($type, $cert, %extra) = @_;
	$type = 'PSS' if $type eq 'RSA' && $version > 0x0303;
	my ($s, $ssl) = get_ssl_socket($type, $cert, %extra);
	my $cipher = Net::SSLeay::get_cipher($ssl);
	Test::Nginx::log_core('||', "cipher: $cipher");
	my $host = $extra{sni} ? $extra{sni} : 'localhost';
	Net::SSLeay::write($ssl, "GET /serial HTTP/1.0\nHost: $host\n\n");
	my $r = Net::SSLeay::read($ssl);
	Test::Nginx::log_core($r);
	$s->close();
	return $r unless wantarray();
	return ($s, $ssl);
}

sub get_ssl_socket {
	my ($type, $cert, %extra) = @_;
	my $ses = $extra{ses};
	my $sni = $extra{sni};
	my $port = $extra{port} || 8443;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::INET->new('127.0.0.1:' . port($port));
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

	Net::SSLeay::set_cert_and_key($ctx, "$d/$cert.crt", "$d/$cert.key")
		or die if $cert;
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_session($ssl, $ses) if defined $ses;
	Net::SSLeay::set_tlsext_host_name($ssl, $sni) if $sni;
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
}

sub get_version {
	my ($s, $ssl) = get_ssl_socket();
	return Net::SSLeay::version($ssl);
}

###############################################################################

sub http_daemon {
	my ($t, $port) = @_;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:$port",
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';
		my $resp;

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+\/([^ ]+)\s+HTTP/i;
		next unless $uri;

		$uri =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		my $req = decode_base64($uri);

		if (index($req, $serial_int) > 0) {
			$resp = 'int-resp';

		} elsif (index($req, $serial) > 0) {
			$resp = 'resp';

			# used to differentiate ssl_ocsp_responder

			if ($port == port(8081) && -e "$d/revoked.der") {
				$resp = 'revoked';
			}

		} else {
			$resp = 'ec-resp';
		}

		next unless -s "$d/$resp.der";

		# ocsp dummy handler

		select undef, undef, undef, 0.02;

		$headers = <<"EOF";
HTTP/1.1 200 OK
Connection: close
Content-Type: application/ocsp-response

EOF

		local $/;
		open my $fh, '<', "$d/$resp.der"
			or die "Can't open $resp.der: $!";
		binmode $fh;
		my $content = <$fh>;
		close $fh;

		print $client $headers . $content;
	}
}

###############################################################################
