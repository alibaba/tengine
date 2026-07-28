#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for geo module with volatile.

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

my $t = Test::Nginx->new()->has(qw/http rewrite geo/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $arg_ip $uri_cached {
        192.0.2.1    /1/redirect;
        192.0.2.2    uncached;
    }

    geo $arg_ip $uri_uncached {
        volatile;

        192.0.2.1    /2/redirect;
        192.0.2.2    uncached;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /1 {
            index $uri_cached;
        }
        location /1/redirect {
            set $args ip=192.0.2.2;
            add_header X-URI $uri_cached always;
        }

        location /2 {
            index $uri_uncached;
        }
        location /2/redirect {
            set $args ip=192.0.2.2;
            add_header X-URI $uri_uncached always;
        }
    }
}

EOF

$t->try_run('no geo volatile')->plan(2);

###############################################################################

like(http_get('/1/?ip=192.0.2.1'), qr!X-URI: /1/redirect!, 'geo');
like(http_get('/2/?ip=192.0.2.1'), qr/X-URI: uncached/, 'geo volatile');

###############################################################################
