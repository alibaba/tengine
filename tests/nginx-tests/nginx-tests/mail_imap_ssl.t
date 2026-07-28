#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx mail imap module with ssl.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()
	->has(qw/mail mail_ssl imap http rewrite socket_ssl_sslversion/)
	->has_daemon('openssl')->plan(13)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    proxy_timeout  15s;
    auth_http  http://127.0.0.1:8080/mail/auth;
    auth_http_pass_client_cert on;

    ssl_certificate_key 1.example.com.key;
    ssl_certificate 1.example.com.crt;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;
    }

    server {
        listen     127.0.0.1:8993 ssl;
        protocol   imap;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen     127.0.0.1:8994 ssl;
        protocol   imap;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen     127.0.0.1:8995 ssl;
        protocol   imap;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen     127.0.0.1:8996 ssl;
        protocol   imap;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate 2.example.com.crt;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format  test  '$http_auth_ssl:$http_auth_ssl_verify:'
                      '$http_auth_ssl_subject:$http_auth_ssl_issuer:'
                      '$http_auth_ssl_serial:$http_auth_ssl_fingerprint:'
                      '$http_auth_ssl_cert:$http_auth_pass';
    log_format  test2 '$http_auth_ssl_cipher:$http_auth_ssl_protocol';

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            access_log auth.log test;
            access_log auth2.log test2;

            add_header Auth-Status OK;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port %%PORT_8144%%;
            add_header Auth-Wait 1;
            return 204;
        }
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

foreach my $name ('1.example.com', '2.example.com', '3.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run_daemon(\&Test::Nginx::IMAP::imap_test_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8144));

###############################################################################

my $cred = sub { encode_base64("\0test\@example.com\0$_[0]", '') };

# no ssl connection

my $s = Test::Nginx::IMAP->new();
$s->ok('plain connection');
$s->send('1 AUTHENTICATE PLAIN ' . $cred->("s1"));

# no cert

$s = Test::Nginx::IMAP->new(SSL => 1);
$s->check(qr/BYE No required SSL certificate/, 'no cert');

# no cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:' . port(8994), SSL => 1);
$s->ok('no optional cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred->("s2"));

# wrong cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:' . port(8995),
	SSL => 1,
	SSL_cert_file => "$d/1.example.com.crt",
	SSL_key_file => "$d/1.example.com.key"
);
$s->check(qr/BYE SSL certificate error/, 'bad optional cert');

# wrong cert with ssl_verify_client optional_no_ca

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:' . port(8996),
	SSL => 1,
	SSL_cert_file => "$d/1.example.com.crt",
	SSL_key_file => "$d/1.example.com.key"
);
$s->ok('bad optional_no_ca cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred->("s3"));

# matching cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:' . port(8995),
	SSL => 1,
	SSL_cert_file => "$d/2.example.com.crt",
	SSL_key_file => "$d/2.example.com.key"
);
$s->ok('good cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred->("s4"));

# trusted cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:' . port(8995),
	SSL => 1,
	SSL_cert_file => "$d/3.example.com.crt",
	SSL_key_file => "$d/3.example.com.key"
);
$s->ok('trusted cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred->("s5"));
$s->read();

# Auth-SSL-Protocol and Auth-SSL-Cipher headers

my ($cipher, $sslversion);

$s = Test::Nginx::IMAP->new(SSL => 1);
$cipher = $s->socket()->get_cipher();
$sslversion = $s->socket()->get_sslversion();
$sslversion =~ s/_/./;

undef $s;

# test auth_http request header fields with access_log

$t->stop();

my $f = $t->read_file('auth.log');

like($f, qr/^-:-:-:-:-:-:-\x0d?\x0a?:s1$/m, 'log - plain connection');
like($f, qr/^on:NONE:-:-:-:-:-\x0d?\x0a?:s2$/m, 'log - no cert');
like($f, qr!^on:FAILED(?:.*):(/?CN=1.example.com):\1:\w+:\w+:[^:]+:s3$!m,
	'log - bad cert');
like($f, qr!^on:SUCCESS:(/?CN=2.example.com):\1:\w+:\w+:[^:]+:s4$!m,
	'log - good cert');
like($f, qr!^on:SUCCESS:(/?CN=3.example.com):\1:\w+:\w+:[^:]+:s5$!m,
	'log - trusted cert');

$f = $t->read_file('auth2.log');
like($f, qr|^$cipher:$sslversion$|m, 'log - cipher sslversion');

###############################################################################
