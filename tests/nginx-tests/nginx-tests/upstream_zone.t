#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream zone.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        zone u 1m;
        server 127.0.0.1:8081;
    }

    upstream u2 {
        zone u;
        server 127.0.0.1:8081 down;
        server 127.0.0.1:8081 backup down;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {}
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Name $upstream_addr always;

        location / {
            proxy_pass http://u/;
        }

        location /down {
            proxy_pass http://u2/;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

my $p = port(8081);

like(http_get('/'), qr/X-Name: 127.0.0.1:$p/, 'upstream name');
like(http_get('/down'), qr/X-Name: u2/, 'no live upstreams');

###############################################################################
