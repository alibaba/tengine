#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests that stream health-check state survives a reload.
#
# HTTP and stream peers share one shared memory zone, and the zone is looked up
# on reload by "generation - 1" to inherit peer health. Each side creating the
# zone would bump the generation twice, the lookup would miss, and every peer --
# HTTP ones included -- would fall back to default_down and be probed from
# scratch, taking live traffic with it. That is what this guards.

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

    # an HTTP upstream checked at the same time, so the shared generation is
    # exercised from both sides
    upstream http_backend {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=300 rise=1 fall=1 timeout=250 type=tcp;
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

    upstream stream_backend {
        server 127.0.0.1:%%PORT_8081%%;
        server 127.0.0.1:%%PORT_8082%%;

        check interval=300 rise=1 fall=1 timeout=250 type=tcp;
    }

    server {
        listen      127.0.0.1:%%PORT_8090%%;
        proxy_pass  stream_backend;
    }
}

EOF

$t->run_daemon(\&tcp_daemon, port(8081));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my ($port1, $port2) = (port(8081), port(8082));

# Peers start out down and the first probe fires after a random delay of up to
# max(interval, 1s), so wait for the first verdict.
select undef, undef, undef, 2.5;

my $status = get_status();

like($status, qr!^\d+,http_backend,\S+,up,!m, 'http peer up before reload');
like($status, qr!^\d+,stream_backend,127\.0\.0\.1:$port1,up,!m,
	'stream peer up before reload');
like($status, qr!^\d+,stream_backend,127\.0\.0\.1:$port2,down,!m,
	'dead stream peer down before reload');

my $generation = get_generation();
is($generation, 1, 'one generation before reload');

# The rise counters keep climbing for as long as a peer stays up, so they say
# whether the state was inherited or rebuilt. Comparing them across the reload
# is what makes this test sensitive: "still up" alone would also pass on a peer
# that lost its state and was simply probed again in the meantime.
my $stream_rise = get_rise('stream_backend', $port1);
my $http_rise = get_rise('http_backend', $port1);

cmp_ok($stream_rise, '>', 1, 'stream peer has risen several times');

$t->reload();

select undef, undef, undef, 1;

$status = get_status();

# The generation must advance by exactly one. Two means both sides created a
# zone, so the "generation - 1" lookup that inherits peer health missed.
is(get_generation(), $generation + 1, 'generation advances by one on reload');

like($status, qr!^\d+,stream_backend,127\.0\.0\.1:$port1,up,!m,
	'stream peer still up right after reload');
like($status, qr!^\d+,http_backend,\S+,up,!m,
	'http peer still up right after reload');

# Counters carried over rather than restarting from zero.
cmp_ok(get_rise('stream_backend', $port1), '>=', $stream_rise,
	'stream peer rise counter inherited');
cmp_ok(get_rise('http_backend', $port1), '>=', $http_rise,
	'http peer rise counter inherited');

# A peer that was down stays down: inheritance must not resurrect it either.
like($status, qr!^\d+,stream_backend,127\.0\.0\.1:$port2,down,!m,
	'dead stream peer still down right after reload');

###############################################################################

sub get_status {
	my $r = http_get('/status?format=csv');
	$r =~ s/.*?\x0d\x0a\x0d\x0a//s;
	return $r;
}

sub get_generation {
	my $r = http_get('/status?format=json');
	return $r =~ /"generation":\s*(\d+)/ ? $1 : undef;
}

# CSV columns: index,upstream,name,status,rise,fall,type,port,protocol
sub get_rise {
	my ($upstream, $peer_port) = @_;

	for my $line (split /\n/, get_status()) {
		my @f = split /,/, $line;
		next unless @f >= 5;
		next unless $f[1] eq $upstream && $f[2] =~ /:$peer_port$/;
		return $f[4];
	}

	return -1;
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
