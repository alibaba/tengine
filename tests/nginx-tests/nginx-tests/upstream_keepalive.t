#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream keepalive directives.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_keepalive/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server 127.0.0.1:8081;
        keepalive 1;
        keepalive_requests 3;
        keepalive_timeout 2s;
    }

    upstream time {
        server 127.0.0.1:8081;
        keepalive 1;
        keepalive_time 2s;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_http_version 1.1;
        proxy_set_header Connection $args;

        location / {
            proxy_pass http://backend;
        }

        location /time {
            proxy_pass http://time/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Connection $connection;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->run()->plan(11);

###############################################################################

my ($r, $n, $m);

# keepalive_requests

like($r = http_get('/'), qr/SEE-THIS/, 'request');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/'), qr/X-Connection: $n.*SEE/ms, 'keepalive');
like(http_get('/'), qr/X-Connection: $n.*SEE/ms, 'keepalive again');
like(http_get('/'), qr/X-Connection: (?!$n).*SEE/ms, 'keepalive requests');
http_get('/?close');

# keepalive_timeout, keepalive_time

like($r = http_get('/'), qr/SEE-THIS/, 'request timer');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like($r = http_get('/time'), qr/SEE-THIS/, 'request time');
$r =~ m/X-Connection: (\d+)/; $m = $1;

like(http_get('/'), qr/X-Connection: $n.*SEE/ms, 'keepalive timer');
like(http_get('/time'), qr/X-Connection: $m.*SEE/ms, 'keepalive time');

select undef, undef, undef, 2.5;

like(http_get('/'), qr/X-Connection: (?!$n).*SEE/ms, 'keepalive timeout');
like(http_get('/time'), qr/X-Connection: $m.*SEE/ms, 'keepalive time last');
like(http_get('/time'), qr/X-Connection: (?!$m).*SEE/ms, 'keepalive time new');

###############################################################################
