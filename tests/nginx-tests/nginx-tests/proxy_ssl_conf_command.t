#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy_ssl_conf_command and friends.

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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl proxy uwsgi http_v2 grpc openssl:1.0.2/)
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

        location / {
            proxy_ssl_certificate localhost.crt;
            proxy_ssl_certificate_key localhost.key;
            proxy_ssl_conf_command Certificate override.crt;
            proxy_ssl_conf_command PrivateKey override.key;
            proxy_pass https://127.0.0.1:8081;
        }

        location /uwsgi {
            uwsgi_ssl_certificate localhost.crt;
            uwsgi_ssl_certificate_key localhost.key;
            uwsgi_ssl_conf_command Certificate override.crt;
            uwsgi_ssl_conf_command PrivateKey override.key;
            uwsgi_ssl_session_reuse off;
            uwsgi_pass suwsgi://127.0.0.1:8081;
        }

        location /grpc {
            grpc_ssl_certificate localhost.crt;
            grpc_ssl_certificate_key localhost.key;
            grpc_ssl_conf_command Certificate override.crt;
            grpc_ssl_conf_command PrivateKey override.key;
            grpc_pass grpcs://127.0.0.1:8082;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        http2 on;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
        ssl_verify_client optional_no_ca;

        # stub to implement SSL logic for tests

        add_header X-Cert $ssl_client_s_dn always;
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

foreach my $name ('localhost', 'override') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');
$t->try_run('no ssl_conf_command')->plan(3);

###############################################################################

like(http_get('/'), qr/CN=override/, 'proxy_ssl_conf_command');
like(http_get('/uwsgi'), qr/CN=override/, 'uwsgi_ssl_conf_command');
like(http_get('/grpc'), qr/CN=override/, 'grpc_ssl_conf_command');

###############################################################################
