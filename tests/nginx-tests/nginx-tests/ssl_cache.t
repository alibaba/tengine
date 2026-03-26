#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for SSL object cache.

###############################################################################

use warnings;
use strict;

use Test::More;

use POSIX qw/ mkfifo /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new();

plan(skip_all => "not yet") unless $t->has_version('1.27.2');

$t->has(qw/http http_ssl proxy socket_ssl/)->has_daemon('openssl')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  1.example.com;

        ssl_certificate 1.example.com.crt.fifo;
        ssl_certificate_key 1.example.com.key.fifo;

        ssl_trusted_certificate root.crt.fifo;
        ssl_crl root.crl.fifo;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  1.example.com;

        ssl_certificate %%TESTDIR%%/1.example.com.crt.fifo;
        ssl_certificate_key %%TESTDIR%%/1.example.com.key.fifo;

        ssl_trusted_certificate %%TESTDIR%%/root.crt.fifo;
        ssl_crl %%TESTDIR%%/root.crl.fifo;
    }

    server {
        listen       127.0.0.1:8445 ssl;
        server_name  2.example.com;

        add_header X-Verify $ssl_client_verify:$ssl_client_s_dn;

        ssl_certificate 2.example.com.crt.fifo;
        ssl_certificate_key 2.example.com.key.fifo;

        ssl_verify_client on;
        ssl_client_certificate root.crt.fifo;
        ssl_crl root.crl.fifo;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass https://127.0.0.1:8445;

            proxy_ssl_certificate 1.example.com.crt.fifo;
            proxy_ssl_certificate_key 1.example.com.key.fifo;

            proxy_ssl_name 2.example.com;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate root.crt.fifo;
            proxy_ssl_crl root.crl.fifo;
        }
    }
}

EOF

my $d = $t->testdir();

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

[ myca_policy ]
commonName = supplied
EOF

foreach my $name ('root') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";

	system("openssl ca -batch -config $d/ca.conf "
		. "-keyfile $d/root.key -cert $d/root.crt "
		. "-subj /CN=$name/ -in $d/$name.csr -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't sign certificate for $name: $!\n";
}

system("openssl ca -gencrl -config $d/ca.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-out $d/root.crl -crldays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't update crl: $!\n";

foreach my $name ('root.crt', 'root.crl', '1.example.com.crt',
	'1.example.com.key', '2.example.com.crt', '2.example.com.key')
{
	mkfifo("$d/$name.fifo", 0700);
	$t->run_daemon(\&fifo_writer_daemon, $t, $name);
}

$t->write_file('t', '');

$t->plan(4)->run();

###############################################################################

like(get(8443, '1.example.com'), qr/200 OK/, 'cached certificate');
like(get(8444, '1.example.com'), qr/200 OK/, 'absolute path');

like(get(8445, '2.example.com', '1.example.com'),
	qr/200 OK.*SUCCESS:.*1\.example\.com/s, 'cached CA and CRL');

like(http_get('/t'), qr/200 OK.*SUCCESS:.*1\.example\.com/s, 'proxy ssl');

###############################################################################

sub get {
	my ($port, $ca, $cert) = @_;

	$ca = undef if $IO::Socket::SSL::VERSION < 2.062
		|| !eval { Net::SSLeay::X509_V_FLAG_PARTIAL_CHAIN() };

	http_get('/t',
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		$ca ? (
		SSL_ca_file => "$d/$ca.crt",
		SSL_verifycn_name => $ca,
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER(),
		) : (),
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : ()
	);
}

###############################################################################

sub fifo_writer_daemon {
	my ($t, $name) = @_;

	my $content = $t->read_file($name);

	while (1) {
		$t->write_file("$name.fifo", $content);
		# reset content after the first read
		$content = "";
	}
}

###############################################################################
