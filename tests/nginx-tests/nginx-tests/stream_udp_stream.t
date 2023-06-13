#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for UDP stream.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ dgram /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return udp/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_timeout   1s;

    server {
        listen      127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass  127.0.0.1:%%PORT_8981_UDP%%;
    }

    server {
        listen      127.0.0.1:%%PORT_8981_UDP%% udp;
        return      $remote_port;
    }
}

EOF

$t->run();

###############################################################################

my $s = dgram('127.0.0.1:' . port(8980));
my $data = $s->io('1', read_timeout => 0.5);
isnt($data, '', 'udp_stream response 1');

my $s2 = dgram('127.0.0.1:' . port(8980));
my $data2 = $s2->io('1', read_timeout => 0.5);
isnt($data2, '', 'udp_stream response 2');

isnt($data, $data2, 'udp_stream two sessions');

is($s->io('1'), $data, 'udp_stream session 1');
is($s->io('1'), $data, 'udp_stream session 2');

is($s2->io('1'), $data2, 'udp_stream another session 1');
is($s2->io('1'), $data2, 'udp_stream another session 2');

select undef, undef, undef, 1.1;

isnt($s->io('1'), $data, 'udp_stream new session');

###############################################################################
