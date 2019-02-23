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

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL::SSL_VERIFY_NONE(); };
plan(skip_all => 'IO::Socket::SSL too old') if $@;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()
	->has(qw/mail mail_ssl imap http rewrite/)->has_daemon('openssl')
	->run_daemon(\&Test::Nginx::IMAP::imap_test_daemon)->plan(12);

$t->todo_alerts() if $^O eq 'solaris';

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;
    auth_http_pass_client_cert on;

    ssl_certificate_key 1.example.com.key;
    ssl_certificate 1.example.com.crt;

    server {
        listen     127.0.0.1:8142;
        protocol   imap;
    }

    server {
        listen     127.0.0.1:8143 ssl;
        protocol   imap;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen     127.0.0.1:8145 ssl;
        protocol   imap;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen     127.0.0.1:8146 ssl;
        protocol   imap;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen     127.0.0.1:8147 ssl;
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
                      '$http_auth_ssl_cert';

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            access_log auth.log test;

            add_header Auth-Status OK;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port 8144;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('1.example.com', '2.example.com', '3.example.com') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

my $cred = encode_base64("\0test\@example.com\0secret", '');
my %ssl = (
	SSL => 1,
	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
	SSL_error_trap => sub { die $_[1] },
);

# no ssl connection

my $s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:8142');
$s->ok('plain connection');
$s->send('1 AUTHENTICATE PLAIN ' . $cred);

# no cert

$s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:8143', %ssl);
$s->check(qr/BYE No required SSL certificate/, 'no cert');

# no cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:8145', %ssl);
$s->ok('no optional cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred);

# wrong cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:8145',
	SSL_cert_file => "$d/1.example.com.crt",
	SSL_key_file => "$d/1.example.com.key",
	%ssl,
);
$s->check(qr/BYE SSL certificate error/, 'bad optional cert');

# wrong cert with ssl_verify_client optional_no_ca

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:8147',
	SSL_cert_file => "$d/1.example.com.crt",
	SSL_key_file => "$d/1.example.com.key",
	%ssl,
);
$s->ok('bad optional_no_ca cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred);

# matching cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:8145',
	SSL_cert_file => "$d/2.example.com.crt",
	SSL_key_file => "$d/2.example.com.key",
	%ssl,
);
$s->ok('good cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred);

# trusted cert with ssl_verify_client optional

$s = Test::Nginx::IMAP->new(
	PeerAddr => '127.0.0.1:8146',
	SSL_cert_file => "$d/3.example.com.crt",
	SSL_key_file => "$d/3.example.com.key",
	%ssl,
);
$s->ok('trusted cert');
$s->send('1 AUTHENTICATE PLAIN ' . $cred);
$s->read();

# test auth_http request header fields with access_log

$t->stop();

open my $f, '<', $t->testdir() . '/' . 'auth.log'
	or die "Can't open auth.log: $!";

like($f->getline(), qr/^-:-:-:-:-:-:-\x0d?\x0a?$/, 'log - plain connection');
like($f->getline(), qr/^on:NONE:-:-:-:-:-\x0d?\x0a?$/,
	'log - no cert');
like($f->getline(),
	qr!^on:FAILED:/CN=1.example.com:/CN=1.example.com:\w+:\w+:[^:]+$!,
	'log - bad cert');
like($f->getline(),
	qr!^on:SUCCESS:/CN=2.example.com:/CN=2.example.com:\w+:\w+:[^:]+$!,
	'log - good cert');
like($f->getline(),
	qr!^on:SUCCESS:/CN=3.example.com:/CN=3.example.com:\w+:\w+:[^:]+$!,
	'log - trusted cert');

###############################################################################
