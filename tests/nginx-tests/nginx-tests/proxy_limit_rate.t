#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for the proxy_limit_rate directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_keepalive/)->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8080;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8080/data;
            proxy_buffer_size 4k;
            proxy_limit_rate 20000;
            add_header X-Msec $msec;
        }

        location /keepalive {
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_pass http://u/data;
            proxy_buffer_size 4k;
            proxy_limit_rate 20000;
            add_header X-Msec $msec;
        }

        location /data {
        }
    }
}

EOF

$t->write_file('data', 'X' x 40000);
$t->run();

###############################################################################

my $r = http_get('/');

my ($t1) = $r =~ /X-Msec: (\d+)/;
my $diff = time() - $t1;

# four chunks are split with three 1s delays

cmp_ok($diff, '>=', 1, 'proxy_limit_rate');
like($r, qr/^(XXXXXXXXXX){4000}\x0d?\x0a?$/m, 'response body');

# in case keepalive connection was saved with the delayed flag,
# the read timer used to be a delay timer in the next request

like(http_get('/keepalive'), qr/200 OK/, 'keepalive');
like(http_get('/keepalive'), qr/200 OK/, 'keepalive 2');

###############################################################################
