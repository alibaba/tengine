#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests that health-check state is inherited per peer, not per address.
#
# An address is not a peer: the same server may be listed by several upstreams,
# and the HTTP and the stream side share one shared memory zone, so one address
# has as many records as upstreams that list it. Looking the previous record up
# by address alone made every peer with that address inherit the state of
# whichever one came first, silently swapping health across upstreams and across
# protocols on every reload -- a peer known to be up could come back down, and a
# dead one could come back up and take live traffic.
#
# The peers here differ only in how often they are probed, two orders of
# magnitude apart, so the rise counter says which record a peer inherited: a
# slowly probed peer that suddenly shows a high count took over the fast peer's
# record, and a fast one that drops to a low count took over the slow peer's.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream http upstream_check/)->plan(11)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    # Both backend addresses are listed twice on the HTTP side and once on the
    # stream side, in an order that puts a fast peer first for one address and a
    # slow peer first for the other. That way a lookup by address alone is
    # caught whichever direction it drifts in.

    upstream http_fast_a {
        server 127.0.0.1:%%PORT_8081%%;
        check interval=100 rise=1 fall=1 timeout=90 type=tcp;
    }

    upstream http_slow_a {
        server 127.0.0.1:%%PORT_8081%%;
        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp;
    }

    upstream http_slow_b {
        server 127.0.0.1:%%PORT_8082%%;
        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp;
    }

    upstream http_fast_b {
        server 127.0.0.1:%%PORT_8082%%;
        check interval=100 rise=1 fall=1 timeout=90 type=tcp;
    }

    # An upstream of this name exists on the stream side too, on the same
    # address: nothing but the protocol tells the two records apart.
    upstream shared_name {
        server 127.0.0.1:%%PORT_8083%%;
        check interval=100 rise=1 fall=1 timeout=90 type=tcp;
    }

    server {
        listen      127.0.0.1:%%PORT_8080%%;
        server_name localhost;

        location /status {
            check_status;
            access_log off;
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream stream_slow_a {
        server 127.0.0.1:%%PORT_8081%%;
        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp;
    }

    upstream stream_fast_b {
        server 127.0.0.1:%%PORT_8082%%;
        check interval=100 rise=1 fall=1 timeout=90 type=tcp;
    }

    upstream shared_name {
        server 127.0.0.1:%%PORT_8083%%;
        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp;
    }

    server {
        listen      127.0.0.1:%%PORT_8090%%;
        proxy_pass  stream_slow_a;
    }

    server {
        listen      127.0.0.1:%%PORT_8091%%;
        proxy_pass  stream_fast_b;
    }

    server {
        listen      127.0.0.1:%%PORT_8092%%;
        proxy_pass  shared_name;
    }
}

EOF

$t->run_daemon(\&tcp_daemon, port(8081));
$t->run_daemon(\&tcp_daemon, port(8082));
$t->run_daemon(\&tcp_daemon, port(8083));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));
$t->waitforsocket('127.0.0.1:' . port(8083));

###############################################################################

# The first probe of a peer fires after a random delay of up to one second, so
# give every peer time for that plus a handful of intervals.
select undef, undef, undef, 4;

my %before = get_rise();

# Sanity: the fast peers have been probed an order of magnitude more often than
# the slow ones, which is what makes the counters tell the records apart.
cmp_ok($before{'http_fast_a:http'}, '>', 15, 'fast http peer probed often');
cmp_ok($before{'http_fast_b:http'}, '>', 15,
	'fast http peer probed often, 2nd addr');
cmp_ok($before{'stream_fast_b:stream'}, '>', 15,
	'fast stream peer probed often');
cmp_ok($before{'http_slow_a:http'}, '<', 5, 'slow http peer probed rarely');
cmp_ok($before{'stream_slow_a:stream'}, '<', 5,
	'slow stream peer probed rarely');
cmp_ok($before{'shared_name:stream'}, '<', 5,
	'slow stream peer probed rarely, same upstream name');

$t->reload();

select undef, undef, undef, 1;

my %after = get_rise();

# A slow peer whose count jumped to the fast peer's magnitude inherited the
# wrong record: same address, different upstream.
cmp_ok($after{'http_slow_a:http'}, '<', 10,
	'slow http peer kept its own record');
cmp_ok($after{'stream_slow_a:stream'}, '<', 10,
	'slow stream peer kept its own record');

# Same address and same upstream name, HTTP and stream: only the protocol keeps
# these two apart.
cmp_ok($after{'shared_name:stream'}, '<', 10,
	'stream peer kept its own record against an HTTP namesake');

# And the other way round: a fast peer that fell back to a slow peer's count
# lost its own history. Here the slow peer on that address comes first.
cmp_ok($after{'http_fast_b:http'}, '>=', $before{'http_fast_b:http'},
	'fast http peer kept its own record');
cmp_ok($after{'stream_fast_b:stream'}, '>=', $before{'stream_fast_b:stream'},
	'fast stream peer kept its own record');

###############################################################################

# CSV columns: index,upstream,name,status,rise,fall,type,port,protocol
sub get_rise {
	my %rise;

	my $r = http_get('/status?format=csv');
	$r =~ s/.*?\x0d\x0a\x0d\x0a//s;

	for my $line (split /\n/, $r) {
		my @f = split /,/, $line;
		next unless @f >= 9;
		$rise{"$f[1]:$f[8]"} = $f[4];
	}

	return %rise;
}

###############################################################################

sub tcp_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buffer, 65536);
		$client->syswrite($client->sockport());
		$client->close;
	}
}

###############################################################################
