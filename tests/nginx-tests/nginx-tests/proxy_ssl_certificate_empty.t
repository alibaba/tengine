#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module with proxy certificate to ssl backend.
# The proxy_ssl_certificate directive empty value cancels inheritance.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy/)
	->has_daemon('openssl');

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

        proxy_ssl_session_reuse off;

        proxy_ssl_certificate 1.example.com.crt;
        proxy_ssl_certificate_key 1.example.com.key;

        location /verify {
            proxy_pass https://127.0.0.1:8081/;
        }

        location /cancel {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_certificate "";
            proxy_ssl_certificate_key "";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate 2.example.com.crt;
        ssl_certificate_key 2.example.com.key;

        ssl_verify_client optional;
        ssl_client_certificate 1.example.com.crt;

        location / {
            add_header X-Verify $ssl_client_verify;
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

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

sleep 1 if $^O eq 'MSWin32';

$t->write_file('index.html', '');

$t->try_run('no empty value support')->plan(2);

###############################################################################

like(http_get('/verify'), qr/X-Verify: SUCCESS/ms, 'verify certificate');
like(http_get('/cancel'), qr/X-Verify: NONE/ms, 'cancel certificate');

###############################################################################
