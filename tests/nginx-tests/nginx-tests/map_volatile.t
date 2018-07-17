#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for map module with volatile.

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

my $t = Test::Nginx->new()->has(qw/http map/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $uri $uri_cached {
        /1/          /1/redirect;
        /1/redirect  uncached;
    }

    map $uri $uri_uncached {
        volatile;

        /2/          /2/redirect;
        /2/redirect  uncached;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /1 {
            index $uri_cached;
        }
        location /1/redirect {
            add_header X-URI $uri_cached always;
        }

        location /2 {
            index $uri_uncached;
        }
        location /2/redirect {
            add_header X-URI $uri_uncached always;
        }
    }
}

EOF

mkdir($t->testdir() . '/1');
mkdir($t->testdir() . '/2');

$t->run()->plan(2);

###############################################################################

like(http_get('/1/'), qr!X-URI: /1/redirect!, 'map');
like(http_get('/2/'), qr/X-URI: uncached/, 'map volatile');

###############################################################################
