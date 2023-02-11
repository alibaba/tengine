#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream geo module with unix socket.

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

my $t = Test::Nginx->new()->has(qw/stream stream_geo stream_return unix/)
	->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    geo $geo {
        default                  default;
        255.255.255.255          none;
    }

    geo $remote_addr $geora {
        default                  default;
        255.255.255.255          none;
    }

    geo $geor {
        ranges;
        0.0.0.0-255.255.255.254  test;
        default                  none;
    }

    geo $remote_addr $georra {
        ranges;
        0.0.0.0-255.255.255.254  test;
        default                  none;
    }

    server {
        listen      unix:%%TESTDIR%%/unix.sock;
        return      "geo:$geo geora:$geora geor:$geor georra:$georra";
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  unix:%%TESTDIR%%/unix.sock;
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

my %data = stream('127.0.0.1:' . port(8080))->read() =~ /(\w+):(\w+)/g;
is($data{geo}, 'none', 'geo unix');
is($data{geor}, 'none', 'geo unix ranges');
is($data{geora}, 'none', 'geo unix remote addr');
is($data{georra}, 'none', 'geo unix ranges remote addr');

###############################################################################
