#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream zone with ssl backend.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
	->has(qw/stream_upstream_zone/)->has_daemon('openssl')->plan(9);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse on;

    upstream u {
        zone u 1m;
        server 127.0.0.1:8084;
    }

    upstream u2 {
        zone u2 1m;
        server 127.0.0.1:8084 backup;
        server 127.0.0.1:8085 down;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;
        proxy_ssl_session_reuse off;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  u2;
        proxy_ssl_session_reuse off;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  u2;
    }

    server {
        listen      127.0.0.1:8084 ssl;
        return      $ssl_session_reused;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        ssl_session_cache builtin;
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

$t->run();

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), '.', 'ssl');
is(stream('127.0.0.1:' . port(8080))->read(), '.', 'ssl 2');

is(stream('127.0.0.1:' . port(8081))->read(), '.', 'ssl session new');
is(stream('127.0.0.1:' . port(8081))->read(), 'r', 'ssl session reused');
is(stream('127.0.0.1:' . port(8081))->read(), 'r', 'ssl session reused 2');

is(stream('127.0.0.1:' . port(8082))->read(), '.', 'backup ssl');
is(stream('127.0.0.1:' . port(8082))->read(), '.', 'backup ssl 2');

is(stream('127.0.0.1:' . port(8083))->read(), '.', 'backup ssl session new');
is(stream('127.0.0.1:' . port(8083))->read(), 'r', 'backup ssl session reused');

###############################################################################
