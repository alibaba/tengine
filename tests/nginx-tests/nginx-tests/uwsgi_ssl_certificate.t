#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http uwsgi module with client certificate to ssl backend.
# The uwsgi_ssl_certificate and uwsgi_ssl_password_file directives.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl uwsgi/)
	->has_daemon('openssl')->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        uwsgi_ssl_session_reuse off;

        location /verify {
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_ssl_certificate 1.example.com.crt;
            uwsgi_ssl_certificate_key 1.example.com.key;
        }

        location /fail {
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_ssl_certificate 2.example.com.crt;
            uwsgi_ssl_certificate_key 2.example.com.key;
        }

        location /encrypted {
            uwsgi_pass suwsgi://127.0.0.1:8082;
            uwsgi_ssl_certificate 3.example.com.crt;
            uwsgi_ssl_certificate_key 3.example.com.key;
            uwsgi_ssl_password_file password;
        }
    }

    # stub to implement SSL logic for tests

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate 2.example.com.crt;
        ssl_certificate_key 2.example.com.key;

        ssl_verify_client optional_no_ca;
        ssl_trusted_certificate 1.example.com.crt;

        add_header X-Verify $ssl_client_verify always;
        add_header X-Name   $ssl_client_s_dn   always;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate 1.example.com.crt;
        ssl_certificate_key 1.example.com.key;

        ssl_verify_client optional_no_ca;
        ssl_trusted_certificate 3.example.com.crt;

        add_header X-Verify $ssl_client_verify always;
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

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('3.example.com') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

sleep 1 if $^O eq 'MSWin32';

$t->write_file('password', '3.example.com');
$t->write_file('index.html', '');

$t->run();

###############################################################################

like(http_get('/verify'), qr/X-Verify: SUCCESS/ms, 'verify certificate');
like(http_get('/fail'), qr/X-Verify: FAILED/ms, 'fail certificate');
like(http_get('/encrypted'), qr/X-Verify: SUCCESS/ms, 'with encrypted key');

like(http_get('/verify'), qr!X-Name: /?CN=1.example!, 'valid certificate');
unlike(http_get('/fail'), qr!X-Name: /?CN=1.example!, 'invalid certificate');

###############################################################################
