#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests stream health checks in a configuration with no http{} block at all,
# plus the peer states that need no status page to observe.
#
# The check timers are registered from the HTTP module's init_process, for peers
# of every protocol. Gating that on the HTTP main configuration -- which a
# stream-only configuration does not have -- leaves every stream peer stuck at
# its initial default_down state, and since a peer the check calls down is
# skipped by the balancer, the upstream stops accepting traffic entirely. That
# failure mode is what the first test here pins down: it needs no status page,
# which is just as well, because check_status is an HTTP location handler and
# cannot exist in this configuration.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream upstream_check/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

# deliberately no http{} block

stream {
    %%TEST_GLOBALS_STREAM%%

    # 8081 is served by a daemon, 8082 is a closed port throughout
    upstream u_rr {
        server 127.0.0.1:%%PORT_8081%%;
        server 127.0.0.1:%%PORT_8082%%;

        check interval=200 rise=1 fall=1 timeout=150 type=tcp;
    }

    # every peer is dead: the check must take the upstream out of service
    # entirely, which proves the probes really run and really mark peers down
    upstream u_all_dead {
        server 127.0.0.1:%%PORT_8082%%;
        server 127.0.0.1:%%PORT_8083%%;

        check interval=200 rise=1 fall=1 timeout=150 type=tcp;
    }

    # the live peer is the backup one, so traffic only reaches it if the check
    # marks the primary down
    upstream u_backup {
        server 127.0.0.1:%%PORT_8082%%;
        server 127.0.0.1:%%PORT_8081%% backup;

        check interval=200 rise=1 fall=1 timeout=150 type=tcp;
    }

    # default_down=false: usable immediately, without waiting for a first probe
    upstream u_default_up {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=200 rise=1 fall=1 timeout=150 type=tcp
              default_down=false;
    }

    server {
        listen      127.0.0.1:%%PORT_8090%%;
        proxy_pass  u_rr;
    }

    server {
        listen      127.0.0.1:%%PORT_8091%%;
        proxy_pass  u_all_dead;
    }

    server {
        listen      127.0.0.1:%%PORT_8092%%;
        proxy_pass  u_backup;
    }

    server {
        listen      127.0.0.1:%%PORT_8093%%;
        proxy_pass  u_default_up;
    }
}

EOF

$t->run_daemon(\&tcp_daemon, port(8081));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $port1 = port(8081);

# default_down=false means this upstream is usable before any probe has run,
# so it is asserted first, while the others are still down.
is(many(port(8093), 3), "$port1: 3", 'default_down=false is usable at once');

# Peers start out down and the first probe fires after a random delay of up to
# max(interval, 1s), so wait for the first verdict.
select undef, undef, undef, 2.5;

is(many(port(8090), 10), "$port1: 10",
	'checked stream upstream works with no http block');

is(many(port(8092), 5), "$port1: 5", 'traffic fails over to the backup peer');

# Nothing answers: with every peer marked down the balancer has nowhere to go,
# so no connection completes. An empty result here is the point.
is(many(port(8091), 3), '', 'upstream with every peer down serves nothing');

# The probes must not be reported as errors in the log.
unlike($t->read_file('error.log'), qr/\[(alert|emerg)\]/,
	'no alerts from the checks');

###############################################################################

sub many {
	my ($port, $count) = @_;
	my (%ports);

	for (1 .. $count) {
		my $s = stream('127.0.0.1:' . $port);
		my $r = eval { $s->io('.') };

		next unless defined $r && $r =~ /(\d+)/;

		$ports{$1} = 0 unless defined $ports{$1};
		$ports{$1}++;
	}

	return join ', ', map { $_ . ": " . $ports{$_} } sort keys %ports;
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
