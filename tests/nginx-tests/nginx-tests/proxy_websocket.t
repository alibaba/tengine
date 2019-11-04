#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy websockets support.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Poll;
use IO::Select;
use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval {
	require Protocol::WebSocket::Handshake::Client;
	require Protocol::WebSocket::Handshake::Server;
	require Protocol::WebSocket::Frame;
};

plan(skip_all => 'Protocol::WebSocket not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http proxy/)
	->write_file_expand('nginx.conf', <<'EOF')->plan(26);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

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
    }
}

EOF

$t->run_daemon(\&websocket_fake_daemon);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start test backend";

###############################################################################

# establish websocket connection

my $s = websocket_connect();
ok($s, "websocket handshake");

SKIP: {
	skip "handshake failed", 22 unless $s;

	# send a frame

	websocket_write($s, 'foo');
	is(websocket_read($s), 'bar', "websocket response");

	# send some big frame

	websocket_write($s, 'foo' x 16384);
	like(websocket_read($s), qr/^(bar){16384}$/, "websocket big response");

	# send multiple frames

	for my $i (1 .. 10) {
		websocket_write($s, ('foo' x 16384) . $i);
		websocket_write($s, 'bazz' . $i);
	}

	for my $i (1 .. 10) {
		like(websocket_read($s), qr/^(bar){16384}\d+$/, "websocket $i");
		is(websocket_read($s), 'bazz' . $i, "websocket small $i");
	}
}

# establish websocket connection with some pipelined data
# and make sure they are correctly passed upstream

undef $s;
$s = websocket_connect("foo");
ok($s, "handshake pipelined");

SKIP: {
	skip "handshake failed", 2 unless $s;

	is(websocket_read($s), "bar", "response pipelined");

	websocket_write($s, "foo");
	is(websocket_read($s), "bar", "next to pipelined");
}

###############################################################################

sub websocket_connect {
	my ($message) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port(8080)
	)
		or die "Can't connect to nginx: $!\n";

	my $h = Protocol::WebSocket::Handshake::Client->new(
		url => 'ws://localhost');

	# send request, $h->to_string

	my $buf = $h->to_string;
	$buf .= Protocol::WebSocket::Frame->new($message)->to_bytes
		if $message;

	local $SIG{PIPE} = 'IGNORE';

	log_out($buf);
	$s->syswrite($buf);

	# read response

	my $got = '';
	$buf = '';

	$s->blocking(0);
	while (IO::Select->new($s)->can_read(1.5)) {
		my $n = $s->sysread($buf, 1024);
		last unless $n;
		log_in($buf);
		$got .= $buf;
		last if $got =~ /\x0d?\x0a\x0d?\x0a$/;
	}

	# parse server response

	$h->parse($got);

	# store the rest for later websocket_read()
	# see websocket_read() for details

	${*$s}->{_websocket_frame} ||= Protocol::WebSocket::Frame->new();
	${*$s}->{_websocket_frame}->append($got);

	return $s if $h->is_done;
}

sub websocket_write {
	my ($s, $message) = @_;
	my $frame = Protocol::WebSocket::Frame->new($message);

	local $SIG{PIPE} = 'IGNORE';
	$s->blocking(1);

	log_out($frame->to_bytes);
	$s->syswrite($frame->to_bytes);
}

sub websocket_read {
	my ($s) = @_;
	my ($buf, $got);

	# store frame object in socket itself to simplify things
	# this works as $s is IO::Handle, see man IO::Handle

	${*$s}->{_websocket_frame} ||= Protocol::WebSocket::Frame->new();
	my $frame = ${*$s}->{_websocket_frame};

	$s->blocking(0);
	$got = $frame->next();
	return $got if defined $got;

	while (IO::Select->new($s)->can_read(1.5)) {
		my $n = $s->sysread($buf, 65536);
		return $got unless $n;
		log_in($buf);
		$frame->append($buf);
		$got = $frame->next();
		return $got if defined $got;
	}
}

###############################################################################

sub websocket_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		websocket_handle_client($client);
	}
}

sub websocket_handle_client {
	my ($client) = @_;

	$client->autoflush(1);
	$client->blocking(0);

	my $poll = IO::Poll->new;

	my $hs = Protocol::WebSocket::Handshake::Server->new;
	my $frame = Protocol::WebSocket::Frame->new;
	my $buffer = '';
	my $closed;
	my $n;

	log2c("(new connection $client)");

	while (1) {
		$poll->mask($client => ($buffer ? POLLIN|POLLOUT : POLLIN));
		my $p = $poll->poll(0.5);
		log2c("(poll $p)");

		foreach ($poll->handles(POLLIN)) {
			$n = $client->sysread(my $chunk, 65536);
			return unless $n;

			log2i($chunk);

			if (!$hs->is_done) {
				unless (defined $hs->parse($chunk)) {
					log2c("(error: " . $hs->error . ")");
					return;
				}

				if ($hs->is_done) {
					$buffer = $hs->to_string;
					log2o($buffer);
				}

				log2c("(parse: $chunk)");
			}

			$frame->append($chunk);

			while (defined(my $message = $frame->next)) {
				my $f;

				if ($frame->is_close) {
					log2c("(close frame)");
					$closed = 1;
					$f = $frame->new(type => 'close')
						->to_bytes;
				} else {
					$message =~ s/foo/bar/g;
					$f = $frame->new($message)->to_bytes;
				}

				log2o($f);
				$buffer .= $f;
			}
		}

		foreach my $writer ($poll->handles(POLLOUT)) {
			next unless length $buffer;
			$n = $writer->syswrite($buffer);
			substr $buffer, 0, $n, '';
		}

		if ($closed && length $buffer == 0) {
			log2c("(closed)");
			return;
		}
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
