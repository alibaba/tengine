#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for addition module with buffered data from other filters.

# In particular, sub filter may have a partial match buffered.

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

my $t = Test::Nginx->new()->has(qw/http proxy sub addition/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / { }
        location /proxy/ {
            sub_filter foo bar;
            add_after_body /after.html;
            proxy_pass http://127.0.0.1:8080/;
        }
    }
}

EOF

$t->write_file('after.html', 'after');
$t->write_file('body.html', 'XXXXX');

$t->run();

###############################################################################

# if data is buffered, there should be no interleaved data in output

like(http_get('/proxy/body.html'), qr/^XXXXXafter$/m, 'request');

###############################################################################
