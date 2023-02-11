#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for URI normalization, merge_slashes off.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        merge_slashes off;

        location / {
            add_header  X-URI  "x $uri x";
            return      204;
        }
    }
}

EOF

###############################################################################

like(http_get('/foo//../bar'), qr!x /foo/bar x!, 'merge slashes');
like(http_get('/foo///../bar'), qr!x /foo//bar x!, 'merge slashes 2');

###############################################################################
