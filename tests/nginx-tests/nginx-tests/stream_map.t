#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream map module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_map/)
	->has(qw/http rewrite/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    map $server_port $x {
        %%PORT_8080%%             literal;
        default                   default;
        ~(%%PORT_8082%%)          $1;
        ~(?P<ncap>%%PORT_8083%%)  $ncap;
    }

    server {
        listen  127.0.0.1:8080;
        listen  127.0.0.1:8081;
        listen  127.0.0.1:8082;
        listen  127.0.0.1:8083;
        return  $x;
    }

    server {
        listen  127.0.0.1:8084;
        return  $x:${x};
    }
}

EOF

$t->run()->plan(5);

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), 'literal', 'literal');
is(stream('127.0.0.1:' . port(8081))->read(), 'default', 'default');
is(stream('127.0.0.1:' . port(8082))->read(), port(8082), 'capture');
is(stream('127.0.0.1:' . port(8083))->read(), port(8083), 'named capture');
is(stream('127.0.0.1:' . port(8084))->read(), 'default:default', 'braces');

###############################################################################
