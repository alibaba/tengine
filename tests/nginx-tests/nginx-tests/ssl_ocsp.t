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
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni socket_ssl_sni/)
	->has_daemon('openssl');

plan(skip_all => 'no OCSP support in BoringSSL')
	if $t->has_module('BoringSSL');

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

    ssl_certificate_key rsa.key;
    ssl_certificate rsa.crt;

    ssl_session_cache shared:SSL:1m;
    ssl_session_tickets off;

    add_header X-Verify x${ssl_client_verify}:${ssl_session_reused}x always;
    add_header X-SSL-Protocol $ssl_protocol always;

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

foreach my $name ('rsa') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run_daemon(\&http_daemon, $t, port(8081));
$t->run_daemon(\&http_daemon, $t, port(8082));
$t->run()->plan(15);

$t->waitforsocket("127.0.0.1:" . port(8081));
$t->waitforsocket("127.0.0.1:" . port(8082));

###############################################################################

like(get('end'), qr/200 OK.*SUCCESS/s, 'ocsp leaf');

# demonstrate that ocsp int request is failed due to missing resolver

like(get('end', sni => 'resolver'),
	qr/400 Bad.*FAILED:certificate status request failed/s,
	'ocsp many failed request');

# demonstrate that ocsp int request is actually made by failing ocsp response

like(get('end', port => 8444),
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

like(get('end', port => 8444), qr/200 OK.*SUCCESS/s, 'ocsp many');

# store into ssl_ocsp_cache

like(get('end', port => 8446), qr/200 OK.*SUCCESS/s, 'cache store');

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

like(get('end'), qr/400 Bad.*FAILED:certificate revoked/s, 'revoked');

# with different responder where it's still valid

like(get('end', port => 8445), qr/200 OK.*SUCCESS/s, 'ocsp responder');

# with different context to responder where it's still valid

like(get('end', sni => 'sni'), qr/200 OK.*SUCCESS/s, 'ocsp context');

# with cached ocsp response it's still valid

like(get('end', port => 8446), qr/200 OK.*SUCCESS/s, 'cache lookup');

# ocsp end response signed with invalid (root) cert, expect HTTP 400

like(get('ec-end'),
	qr/400 Bad.*FAILED:certificate status request failed/s,
	'root ca not trusted');

# now sign ocsp end response with valid int cert

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/int.crt -rkey $d/int.key "
	. "-reqin $d/ec-req.der -respout $d/ec-resp.der -ndays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create EC OCSP response: $!\n";

like(get('ec-end'), qr/200 OK.*SUCCESS/s, 'ocsp ecdsa');

my $s = session('ec-end');

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

like(get('ec-end', ses => $s),
	qr/200 OK.*SUCCESS:r/s, 'session reused');

}

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

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

like(get('ec-end', ses => $s),
	qr/400 Bad.*FAILED:certificate revoked:r/s, 'session reused - revoked');

}

# regression test for self-signed

like(get('root', port => 8447), qr/200 OK.*SUCCESS/s, 'ocsp one');

# check for errors

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crit');

###############################################################################

sub get {
	my $s = get_socket(@_) || return;
	return http_end($s);
}

sub session {
	my $s = get_socket(@_) || return;
	http_end($s);
	return $s;
}

sub get_socket {
	my ($cert, %extra) = @_;
	my $ses = $extra{ses};
	my $sni = $extra{sni} || 'localhost';
	my $port = $extra{port} || 8443;

	return http(
		"GET /serial HTTP/1.0\nHost: $sni\n\n",
		start => 1, PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $sni,
		SSL_session_cache_size => 100,
		SSL_reuse_ctx => $ses,
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : ()
	);
}

sub test_tls13 {
	return http_get('/', SSL => 1) =~ /TLSv1.3/;
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
			Test::Nginx::log_core('||', $_);
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
