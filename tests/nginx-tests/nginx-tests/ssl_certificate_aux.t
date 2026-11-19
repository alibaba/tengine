#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, certificates with trust information.

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

# SSL_load_client_CA_file() doesn't support certificates with trust aux
plan(skip_all => "not yet") unless $t->has_version('1.27.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-SSL-Protocol $ssl_protocol;
    add_header X-Verify $ssl_client_verify;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        ssl_verify_client optional;
        ssl_client_certificate root1-client1.crt;
        ssl_trusted_certificate root2-client2.crt;
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
x509_extensions = myca_extensions
[ req_distinguished_name ]
[ myca_extensions ]
basicConstraints = critical,CA:TRUE
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";

	system('openssl x509 -addtrust serverAuth -trustout '
		. "-in $d/$name.crt -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't add certificate trust for $name: $!\n";
}

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
EOF

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

foreach my $name ('root1', 'root2') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";

	system('openssl x509 -addtrust clientAuth -trustout '
		. "-in $d/$name.crt -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't add certificate trust for $name: $!\n";
}

foreach my $name ('client1', 'client2') {
	my ($num) = $name =~ /(\d)/;
	my $root = "root$num";
	system("openssl	req -new "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out	$d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";

	system("openssl ca -batch -config $d/ca.conf "
		. "-keyfile $d/$root.key -cert $d/$root.crt "
		. "-subj /CN=$name/ -in $d/$name.csr -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't sign certificate for $name: $!\n";

	system('openssl x509 -addtrust clientAuth -trustout '
		. "-in $d/$name.crt -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't add certificate trust for $name: $!\n";

	$t->write_file("$root-$name.crt",
		$t->read_file("$root.crt") . $t->read_file("$name.crt"));
}

$t->write_file('t', '');
$t->run()->plan(3);

###############################################################################

like(get(), qr/200 OK/, 'certificate');
like(get("client1"), qr/200 OK/, 'client certificate');
like(get("client2"), qr/200 OK/, 'trusted certificate');

###############################################################################

sub get {
	my ($cert) = @_;
	http_get("/t",
		SSL => 1,
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : ()
	);
}

###############################################################################
