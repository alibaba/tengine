#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module with datagrams, source address selection.

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

plan(skip_all => '127.0.0.2 local address required')
	unless defined IO::Socket::INET->new( LocalAddr => '127.0.0.2' );

plan(skip_all => 'listen on wildcard address')
	unless $ENV{TEST_NGINX_UNSAFE};

my $t = Test::Nginx->new()->has(qw/stream stream_return udp/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    server {
        listen  %%PORT_8999_UDP%% udp;
        return  $server_addr;
    }
}

EOF

$t->run();

###############################################################################

my $s = dgram(
	LocalAddr => '127.0.0.1',
	PeerAddr  => '127.0.0.2:' . port(8999)
);

is($s->io('test'), '127.0.0.2', 'stream udp wildcard');

###############################################################################
