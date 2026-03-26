#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for proxy with keepalive to ssl backend.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy upstream_keepalive/)
	->has_daemon('openssl')->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_http_version 1.1;

        location / {
            proxy_pass https://u/;
            proxy_set_header Connection $args;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            add_header X-Connection $connection;
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

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', 'SEE-THIS');
$t->run();

###############################################################################

my ($r, $n);

like($r = http_get('/'), qr/200 OK.*SEE-THIS/ms, 'first');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/'), qr/X-Connection: $n[^\d].*SEE-THIS/ms, 'second');

http_get('/?close');
unlike(http_get('/'), qr/X-Connection: $n[^\d]/, 'close');

###############################################################################
