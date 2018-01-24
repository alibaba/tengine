#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for proxy to ssl backend.

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

my $t = Test::Nginx->new()->has(qw/http proxy http_ssl/)->has_daemon('openssl')
	->plan(5)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8081 ssl;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        ssl_session_cache builtin;

        location / {
            add_header X-Session $ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /ssl_reuse {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_session_reuse on;
        }

        location /ssl {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_session_reuse off;
        }

        location /timeout {
            proxy_pass https://127.0.0.1:8081/;
            proxy_connect_timeout 2s;
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

$t->write_file('index.html', '');

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

like(http_get('/ssl'), qr/200 OK.*X-Session: \./s, 'ssl');
like(http_get('/ssl'), qr/200 OK.*X-Session: \./s, 'ssl 2');
like(http_get('/ssl_reuse'), qr/200 OK.*X-Session: \./s, 'ssl reuse session');
like(http_get('/ssl_reuse'), qr/200 OK.*X-Session: r/s, 'ssl reuse session 2');

my $s = http('', start => 1);

sleep 3;

like(http_get('/timeout', socket => $s), qr/200 OK/, 'proxy connect timeout');

###############################################################################
