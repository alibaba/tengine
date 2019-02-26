#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for OCSP stapling.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->has_daemon('openssl');

plan(skip_all => 'no OCSP stapling') if $t->has_module('BoringSSL');

$t->plan(9)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_stapling on;
    ssl_trusted_certificate trusted.crt;

    ssl_certificate ec-end-int.crt;
    ssl_certificate_key ec-end.key;

    ssl_certificate end-int.crt;
    ssl_certificate_key end.key;

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_stapling_responder http://127.0.0.1:8081/;
    }

    server {
        listen       127.0.0.1:8445 ssl;
        server_name  localhost;

        ssl_stapling_verify on;
    }

    server {
        listen       127.0.0.1:8446 ssl;
        server_name  localhost;

        ssl_certificate ec-end.crt;
        ssl_certificate_key ec-end.key;
    }

    server {
        listen       127.0.0.1:8447 ssl;
        server_name  localhost;

        ssl_certificate end-int.crt;
        ssl_certificate_key end.key;

        ssl_stapling_file %%TESTDIR%%/resp.der;
    }

    server {
        listen       127.0.0.1:8448 ssl;
        server_name  localhost;

        ssl_certificate ec-end-int.crt;
        ssl_certificate_key ec-end.key;

        ssl_stapling_file %%TESTDIR%%/ec-resp.der;
    }

    server {
        listen       127.0.0.1:8449 ssl;
        server_name  localhost;

        ssl_stapling_responder http://127.0.0.1:8080/;
    }
}

EOF

my $d = $t->testdir();
my $p = port(8081);

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
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
default_md = sha1
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

system("openssl ca -batch -config $d/ca.conf "
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

system("openssl x509 -in $d/end.crt -serial -noout "
	. ">>$d/serial 2>>$d/openssl.out") == 0
	or die "Can't obtain serial for end: $!\n";

my $serial = pack("n2", 0x0202, hex $1) if $t->read_file('serial') =~ /(\d+)/;

system("openssl ca -config $d/ca.conf -revoke $d/end.crt "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't revoke end.crt: $!\n";

system("openssl ocsp -issuer $d/int.crt -cert $d/end.crt "
	. "-reqout $d/req.der >>$d/openssl.out 2>&1") == 0
	or die "Can't create OCSP request: $!\n";

system("openssl ocsp -index $d/certindex -CA $d/int.crt "
	. "-rsigner $d/root.crt -rkey $d/root.key "
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
$t->write_file('end-int.crt',
	$t->read_file('end.crt') . $t->read_file('int.crt'));
$t->write_file('ec-end-int.crt',
	$t->read_file('ec-end.crt') . $t->read_file('int.crt'));

$t->run_daemon(\&http_daemon, $t);
$t->run();

$t->waitforsocket("127.0.0.1:" . port(8081));

###############################################################################

my $version = get_version();

staple(8443, 'RSA');
staple(8443, 'ECDSA');
staple(8444, 'RSA');
staple(8444, 'ECDSA');
staple(8445, 'ECDSA');
staple(8446, 'ECDSA');
staple(8449, 'ECDSA');

sleep 1;

ok(!staple(8443, 'RSA'), 'staple revoked');
ok(staple(8443, 'ECDSA'), 'staple success');

ok(!staple(8444, 'RSA'), 'responder revoked');
ok(staple(8444, 'ECDSA'), 'responder success');

ok(!staple(8445, 'ECDSA'), 'verify - root not trusted');

ok(staple(8446, 'ECDSA', "$d/int.crt"), 'cert store');

is(staple(8447, 'RSA'), '1 1', 'file revoked');
is(staple(8448, 'ECDSA'), '1 0', 'file success');

ok(!staple(8449, 'ECDSA'), 'ocsp error');

###############################################################################

sub staple {
	my ($port, $ciphers, $ca) = @_;
	my (@resp);

	my $staple_cb = sub {
		my ($ssl, $resp) = @_;
		push @resp, !!$resp;
		return 1 unless $resp;
		my $cert = Net::SSLeay::get_peer_certificate($ssl);
		my $certid = eval { Net::SSLeay::OCSP_cert2ids($ssl, $cert) }
			or do { die "no OCSP_CERTID for certificate: $@"; };

		my @res = Net::SSLeay::OCSP_response_results($resp, $certid);
		push @resp, $res[0][2]->{'statusType'};
	};

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

	my $ssleay = Net::SSLeay::SSLeay();
	if ($ssleay < 0x1000200f || $ssleay == 0x20000000) {
		Net::SSLeay::CTX_set_cipher_list($ctx, $ciphers)
			or die("Failed to set cipher list");
	} else {
		# SSL_CTRL_SET_SIGALGS_LIST
		$ciphers = 'PSS' if $ciphers eq 'RSA' && $version > 0x0303;
		Net::SSLeay::CTX_ctrl($ctx, 98, 0, $ciphers . '+SHA256')
			or die("Failed to set sigalgs");
	}

	Net::SSLeay::CTX_load_verify_locations($ctx, $ca || '', '');
	Net::SSLeay::CTX_set_tlsext_status_cb($ctx, $staple_cb);
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_tlsext_status_type($ssl,
		Net::SSLeay::TLSEXT_STATUSTYPE_ocsp());
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");

	return join ' ', @resp;
}

sub get_version {
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::INET->new('127.0.0.1:' . port(8443));
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");

	Net::SSLeay::version($ssl);
}

###############################################################################

sub http_daemon {
	my ($t) = shift;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:" . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+\/([^ ]+)\s+HTTP/i;
		next unless $uri;

		$uri =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		my $req = decode_base64($uri);
		my $resp = index($req, $serial) > 0 ? 'resp' : 'ec-resp';

		# ocsp dummy handler

		select undef, undef, undef, 0.02;

		$headers = <<"EOF";
HTTP/1.1 200 OK
Connection: close
Content-Type: application/ocsp-response

EOF

		print $client $headers . $t->read_file("$resp.der");
	}
}

###############################################################################
