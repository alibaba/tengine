#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for proxy to ssl backend, use of Server Name Indication
# (proxy_ssl_name, proxy_ssl_server_name directives).

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

my $t = Test::Nginx->new()->has(qw/http http_ssl sni proxy/)
	->has_daemon('openssl')->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server 127.0.0.1:8081;
    }

    upstream backend2 {
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # session reuse is off, as sessions are cached
        # for a particular upstream, and resumed session
        # will use server name previously negotiated

        proxy_ssl_session_reuse off;

        location /1 {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_name 1.example.com;
            proxy_ssl_server_name on;
        }

        location /2 {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_name 2.example.com;
            proxy_ssl_server_name on;

        }

        location /off {
            proxy_pass https://backend/;
            proxy_ssl_server_name off;
        }

        location /default {
            proxy_pass https://backend/;
            proxy_ssl_server_name on;
        }

        location /default2 {
            proxy_pass https://backend2/;
            proxy_ssl_server_name on;
        }

        location /port {
            proxy_pass https://backend/;
            proxy_ssl_server_name on;
            proxy_ssl_name backend:123;
        }

        location /ip {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_server_name on;
        }

        #location /ip6 {
        #    proxy_pass https://[::1]:8081/;
        #    proxy_ssl_server_name on;
        #}
    }

    server {
        listen 127.0.0.1:8081 ssl;
        #listen [::1]:8081 ssl;
        server_name 1.example.com;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        add_header X-Name $ssl_server_name,;
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

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/commonName=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');

$t->run();

###############################################################################

like(http_get('/1'), qr/200 OK.*X-Name: 1.example.com,/ms, 'name 1');
like(http_get('/2'), qr/200 OK.*X-Name: 2.example.com,/ms, 'name 2');
like(http_get('/off'), qr/200 OK.*X-Name: ,/ms, 'no name');

like(http_get('/default'), qr/200 OK.*X-Name: backend,/ms, 'default');
like(http_get('/default2'), qr/200 OK.*X-Name: backend2,/ms, 'default2');
like(http_get('/default'), qr/200 OK.*X-Name: backend,/ms, 'default again');

like(http_get('/port'), qr/200 OK.*X-Name: backend,/ms, 'no port in name');
like(http_get('/ip'), qr/200 OK.*X-Name: ,/ms, 'no ip');
#like(http_get('/ip6'), qr/200 OK.*X-Name: ,/ms, 'no ipv6');

###############################################################################
