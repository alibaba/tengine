#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for access_log with escape parameter.

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

my $t = Test::Nginx->new()->has(qw/stream stream_map stream_return/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    map $pid $a {
        default '" \ "';
    }
    map $pid $b {
        default "foo";
    }

    log_format none     escape=none     $a$b$upstream_addr;

    server {
        listen       127.0.0.1:8080;
        return       ok;

        access_log %%TESTDIR%%/none.log none;
    }
}

EOF

$t->run();

###############################################################################

http_get('/');

$t->stop();

is($t->read_file('none.log'), '" \\ "foo' . "\n", 'none');

###############################################################################
