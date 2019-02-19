#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy upgrade support.
# In contrast to proxy_websocket.t, this test doesn't try to use binary
# WebSocket protocol, but uses simple plain text protocol instead.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Poll;
use IO::Select;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy ssi/)
	->write_file_expand('nginx.conf', <<'EOF')->plan(31);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test "$bytes_sent $body_bytes_sent";
    access_log %%TESTDIR%%/cc.log test;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_read_timeout 2s;
            send_timeout 2s;
        }

        location /ssi.html {
            ssi on;
        }
    }
}

EOF

my $d = $t->testdir();

$t->write_file('ssi.html', '<!--#include virtual="/upgrade" --> SEE-THIS');

$t->run_daemon(\&upgrade_fake_daemon);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start test backend";

###############################################################################

# establish connection

my @r;
my $s = upgrade_connect();
ok($s, "handshake");

SKIP: {
	skip "handshake failed", 22 unless $s;

	# send a frame

	upgrade_write($s, 'foo');
	is(upgrade_read($s), 'bar', "upgrade response");

	# send some big frame

	upgrade_write($s, 'foo' x 16384);
	like(upgrade_read($s), qr/^(bar){16384}$/, "upgrade big response");

	# send multiple frames

	for my $i (1 .. 10) {
		upgrade_write($s, ('foo' x 16384) . $i, continue => 1);
		upgrade_write($s, 'bazz' . $i, continue => $i != 10);
	}

	for my $i (1 .. 10) {
		like(upgrade_read($s), qr/^(bar){16384}\d+$/, "upgrade $i");
		is(upgrade_read($s), 'bazz' . $i, "upgrade small $i");
	}
}

push @r, $s ? ${*$s}->{_upgrade_private}->{r} : 'failed';
undef $s;

# establish connection with some pipelined data
# and make sure they are correctly passed upstream

$s = upgrade_connect(message => "foo");
ok($s, "handshake pipelined");

SKIP: {
	skip "handshake failed", 2 unless $s;

	is(upgrade_read($s), "bar", "response pipelined");

	upgrade_write($s, "foo");
	is(upgrade_read($s), "bar", "next to pipelined");
}

push @r, $s ? ${*$s}->{_upgrade_private}->{r} : 'failed';
undef $s;

# connection should not be upgraded unless upgrade was actually
# requested and allowed by configuration

$s = upgrade_connect(noheader => 1);
ok(!$s, "handshake noupgrade");

# connection upgrade in subrequests shouldn't cause a segfault

SKIP: {
skip 'leaves coredump', 1 unless $t->has_version('1.13.7')
	or $ENV{TEST_NGINX_UNSAFE};

$s = upgrade_connect(uri => '/ssi.html');
ok(!$s, "handshake in subrequests");

}

# bytes sent on upgraded connection
# verify with 1) data actually read by client, 2) expected data from backend

$t->stop();

open my $f, '<', "$d/cc.log" or die "Can't open cc.log: $!";

is($f->getline(), shift (@r) . " 540793\n", 'log - bytes');
is($f->getline(), shift (@r) . " 22\n", 'log - bytes pipelined');
like($f->getline(), qr/\d+ 0\n/, 'log - bytes noupgrade');

###############################################################################

sub upgrade_connect {
	my (%opts) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port(8080),
	)
		or die "Can't connect to nginx: $!\n";

	# send request, $h->to_string

	my $uri = $opts{uri} || '/';

	my $buf = "GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. ($opts{noheader} ? '' : "Upgrade: foo" . CRLF)
		. "Connection: Upgrade" . CRLF . CRLF;

	$buf .= $opts{message} . CRLF . 'FIN' if defined $opts{message};

	local $SIG{PIPE} = 'IGNORE';

	log_out($buf);
	$s->syswrite($buf);

	# read response

	my $got = '';
	$buf = '';

	while (1) {
		$buf = upgrade_getline($s);
		last unless defined $buf and length $buf;
		log_in($buf);
		$got .= $buf;
		last if $got =~ /\x0d?\x0a\x0d?\x0a$/;
	}

	# parse server response

	return if $got !~ m!HTTP/1.1 101!;

	# make sure next line is "handshaked"

	$buf = upgrade_read($s);

	return if !defined $buf or $buf ne 'handshaked';
	return $s;
}

sub upgrade_getline {
	my ($s) = @_;
	my ($h, $buf);

	${*$s}->{_upgrade_private} ||= { b => '', r => 0 };
	$h = ${*$s}->{_upgrade_private};

	if ($h->{b} =~ /^(.*?\x0a)(.*)/ms) {
		$h->{b} = $2;
		return $1;
	}

	$s->blocking(0);
	while (IO::Select->new($s)->can_read(3)) {
		my $n = $s->sysread($buf, 1024);
		last unless $n;

		$h->{b} .= $buf;
		$h->{r} += $n;

		if ($h->{b} =~ /^(.*?\x0a)(.*)/ms) {
			$h->{b} = $2;
			return $1;
		}
	};
}

sub upgrade_write {
	my ($s, $message, %extra) = @_;

	$message = $message . CRLF;
	$message = $message . 'FIN' unless $extra{continue};

	local $SIG{PIPE} = 'IGNORE';

	$s->blocking(0);
	while (IO::Select->new($s)->can_write(1.5)) {
		my $n = $s->syswrite($message);
		last unless $n;
		$message = substr($message, $n);
		last unless length $message;
	}

	if (length $message) {
		$s->close();
	}
}

sub upgrade_read {
	my ($s) = @_;
	my $m = upgrade_getline($s);
	$m =~ s/\x0d?\x0a// if defined $m;
	log_in($m);
	return $m;
}

###############################################################################

sub upgrade_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		upgrade_handle_client($client);
	}
}

sub upgrade_handle_client {
	my ($client) = @_;

	$client->autoflush(1);
	$client->blocking(0);

	my $poll = IO::Poll->new;

	my $handshake = 1;
	my $unfinished = '';
	my $buffer = '';
	my $n;

	log2c("(new connection $client)");

	while (1) {
		$poll->mask($client => ($buffer ? POLLIN|POLLOUT : POLLIN));
		my $p = $poll->poll(0.5);
		log2c("(poll $p)");

		foreach my $reader ($poll->handles(POLLIN)) {
			$n = $client->sysread(my $chunk, 65536);
			return unless $n;

			log2i($chunk);

			if ($handshake) {
				$buffer .= $chunk;
				next unless $buffer =~ /\x0d?\x0a\x0d?\x0a$/;

				log2c("(handshake done)");

				$handshake = 0;
				$buffer = 'HTTP/1.1 101 Switching' . CRLF
					. 'Upgrade: foo' . CRLF
					. 'Connection: Upgrade' . CRLF . CRLF
					. 'handshaked' . CRLF;

				log2o($buffer);

				next;
			}

			$unfinished .= $chunk;

			if ($unfinished =~ m/\x0d?\x0aFIN\z/) {
				$unfinished =~ s/FIN\z//;
				$unfinished =~ s/foo/bar/g;
				log2o($unfinished);
				$buffer .= $unfinished;
				$unfinished = '';
			}
		}

		foreach my $writer ($poll->handles(POLLOUT)) {
			next unless length $buffer;
			$n = $writer->syswrite($buffer);
			substr $buffer, 0, $n, '';
		}
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
