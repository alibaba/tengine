#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for working_directory directive.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
working_directory wd;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
    }
}

EOF

$t->write_file('index.html', '');
mkdir($t->testdir() . '/wd');

$t->run()->plan(1);

###############################################################################

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.8');

like(http_get('/'), qr/200 OK/, 'relative to prefix');

}

$t->todo_alerts() unless $t->has_version('1.31.8');

###############################################################################
