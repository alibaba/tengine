#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for proxy to ssl backend.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl http http_ssl/)
	->has(qw/stream_return/)
	->has_daemon('openssl')->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse on;
    proxy_connect_timeout 2s;

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8083;
        proxy_ssl_session_reuse off;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8083;
    }

    server {
        listen      127.0.0.1:8083 ssl;
        return      $ssl_session_reused;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        ssl_session_cache builtin;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8084;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8084 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
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

$t->write_file('index.html', '');

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

is(stream('127.0.0.1:' . port(8081))->read(), '.', 'ssl');
is(stream('127.0.0.1:' . port(8081))->read(), '.', 'ssl 2');

is(stream('127.0.0.1:' . port(8082))->read(), '.', 'ssl session new');
is(stream('127.0.0.1:' . port(8082))->read(), 'r', 'ssl session reused');
is(stream('127.0.0.1:' . port(8082))->read(), 'r', 'ssl session reused 2');

my $s = http('', start => 1);

sleep 3;

like(http_get('/', socket => $s), qr/200 OK/, 'proxy connect timeout');

###############################################################################
