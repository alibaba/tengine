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

my $t = Test::Nginx->new()->has(qw/stream stream_map stream_return/)
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

    log_format json     escape=json     $a$b$upstream_addr;
    log_format default  escape=default  $a$b$upstream_addr;

    server {
        listen       127.0.0.1:8080;
        return       ok;

        access_log %%TESTDIR%%/json.log json;
        access_log %%TESTDIR%%/test.log default;
    }
}

EOF

$t->run()->plan(2);

###############################################################################

http_get('/');

$t->stop();

is($t->read_file('json.log'), '\" \\\\ \"foo' . "\n", 'json');
is($t->read_file('test.log'), '\x22 \x5C \x22foo-' . "\n", 'default');

###############################################################################
