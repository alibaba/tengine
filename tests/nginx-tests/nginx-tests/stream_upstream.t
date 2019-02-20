#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream module and balancers.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    log_format bytes $upstream_addr!
                     $upstream_bytes_sent!$upstream_bytes_received;

    upstream u {
        server 127.0.0.1:8084;
        server 127.0.0.1:8085;
    }

    upstream u2 {
        server 127.0.0.1:8086 down;
        server 127.0.0.1:8086;
        server 127.0.0.1:8084;
        server 127.0.0.1:8085;
    }

    upstream u3 {
        server 127.0.0.1:8084;
        server 127.0.0.1:8085 weight=2;
    }

    upstream u4 {
        server 127.0.0.1:8086 fail_timeout=1s;
        server 127.0.0.1:8084 backup;
    }

    proxy_connect_timeout 1s;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  u2;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  u3;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  u4;
        access_log  %%TESTDIR%%/u.log bytes;
    }
}

EOF

$t->run_daemon(\&stream_daemon, port(8084));
$t->run_daemon(\&stream_daemon, port(8085));
$t->run()->plan(6);

$t->waitforsocket('127.0.0.1:' . port(8084));
$t->waitforsocket('127.0.0.1:' . port(8085));

###############################################################################

my @ports = my ($port4, $port5, $port6) = (port(8084), port(8085), port(8086));

is(many(30, port(8080)), "$port4: 15, $port5: 15", 'balanced');
is(many(30, port(8081)), "$port4: 15, $port5: 15", 'failures');
is(many(30, port(8082)), "$port4: 10, $port5: 20", 'weight');
is(many(30, port(8083)), "$port4: 30", 'backup');

$t->run_daemon(\&stream_daemon, port(8086));
$t->waitforsocket('127.0.0.1:' . port(8086));

sleep 2;	# wait till fail_timeout passes
is(parallel(30, port(8083)), "$port6: 30", 'recovery');

$t->stop();

like($t->read_file('u.log'), qr/127.0.0.1:$port6, 127.0.0.1:$port4!0, 1!0, 4/,
	'per-upstream variables');

###############################################################################

sub many {
	my ($count, $port) = @_;
	my (%ports);

	for (1 .. $count) {
		if (stream("127.0.0.1:$port")->io('.') =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub parallel {
	my ($count, $port) = @_;
	my (%ports, @s);

	for (1 .. $count) {
		my $s = stream("127.0.0.1:$port");
		$s->write('keep');
		$s->read();
		push @s, $s;
	}

	for (1 .. $count) {
		if ((pop @s)->io('.') =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub stream_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($server == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

	log2i("$client $buffer");

	my $close = $buffer ne 'keep';
	$buffer = $client->sockport();

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $close;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
