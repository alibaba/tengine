#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with unbuffered request body.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        proxy_http_version 1.1;

        location / {
            proxy_request_buffering off;
            proxy_pass http://127.0.0.1:8081/bad;
            proxy_intercept_errors on;
            error_page 502 = /pass;
        }

        location /bad {
            return 502;
        }

        location /pass {
            proxy_pass http://127.0.0.1:8081/good;
        }

        location /good {
            limit_rate 100;
            return 200;
        }
    }
}

EOF

$t->run();

###############################################################################

# unbuffered request body

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ body_more => 1 });

$s->h2_body('SEE-', { body_more => 1 });
sleep 1;
$s->h2_body('THIS');

my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'discard body rest on redirect');

###############################################################################
