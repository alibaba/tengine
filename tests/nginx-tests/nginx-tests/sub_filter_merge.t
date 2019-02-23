#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for sub_filter inheritance from http context.

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

my $t = Test::Nginx->new()->has(qw/http sub/);

$t->plan(1)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    sub_filter foo bar;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('foo.html', 'foo');
$t->run();

###############################################################################

like(http_get('/foo.html'), qr/bar/, 'sub_filter inheritance');

###############################################################################
