#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for index module, which is a helper for testing
# configuration token that starts with a variable.

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

my $t = Test::Nginx->new()->has(qw/http/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        add_header   X-URI $uri;

        location /var/ {
            alias %%TESTDIR%%/;
            index ${server_name}html;
        }
    }
}

EOF

$t->write_file('localhosthtml', 'varbody');

$t->try_run('unsupported token')->plan(1);

###############################################################################

like(http_get('/var/'), qr/X-URI: \/var\/localhosthtml.*varbody/ms, 'var');

###############################################################################
