#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for grpc module, request body buffered.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 grpc mirror proxy/)->plan(12);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:8082;
        server_name  localhost;

        http2 on;

        location /mirror { }

        location / {
            grpc_pass 127.0.0.1:8081;
            add_header X-Body $request_body;
            mirror /mirror;
        }

        location /proxy {
            proxy_pass http://127.0.0.1:8082/mirror;
            proxy_intercept_errors on;
            error_page 404 = @fallback;
        }

        location @fallback {
            grpc_pass 127.0.0.1:8081;
        }
    }
}

EOF

$t->run();

###############################################################################

my $p = port(8081);
my $f = grpc();

my $frames = $f->{http_start}('/SayHello');
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'request - HEADERS flags');
is($frame->{headers}{':method'}, 'POST', 'request - method');
is($frame->{headers}{':scheme'}, 'http', 'request - scheme');
is($frame->{headers}{':path'}, '/SayHello', 'request - path');
is($frame->{headers}{':authority'}, "127.0.0.1:$p", 'request - authority');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello', 'request - DATA');
is($frame->{length}, 5, 'request - DATA length');
is($frame->{flags}, 1, 'request - DATA flags');

$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{'x-body'}, 'Hello', 'request body in memory');

# tcp_nopush usage on peer connections
# reopen window for request body after initial window was exhausted

$frames = $f->{http_start}('/proxy');
is(eval(join '+', map { $_->{length} } grep { $_->{type} eq "DATA" } @$frames),
	65535, 'preserve_output - first body bytes');

# expect body cleanup is disabled with preserve_output (ticket #1565).
# after request body first bytes were proxied on behalf of initial window size,
# send response header from upstream, this leads to body cleanup code path

$frames = $f->{http_end}();
is(eval(join '+', map { $_->{length} } grep { $_->{type} eq "DATA" } @$frames),
	465, 'preserve_output - last body bytes');

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crits');

###############################################################################

sub grpc {
	my ($server, $client, $f, $s, $c, $sid, $uri);

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $p,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	$f->{http_start} = sub {
		($uri, my %extra) = @_;
		$s = Test::Nginx::HTTP2->new() if !defined $s;
		my ($body) = $uri eq '/proxy' ? 'Hello' x 13200 : 'Hello';
		$s->new_stream({ body => $body, headers => [
			{ name => ':method', value => 'POST', mode => 0 },
			{ name => ':scheme', value => 'http', mode => 0 },
			{ name => ':path', value => $uri },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-length', value => length($body) }]});

		if (!$extra{reuse}) {
			eval {
				local $SIG{ALRM} = sub { die "timeout\n" };
				alarm(5);

				$client = $server->accept() or return;

				alarm(0);
			};
			alarm(0);
			if ($@) {
				log_in("died: $@");
				return undef;
			}

			log2c("(new connection $client)");

			$client->sysread(my $buf, 24) == 24 or return; # preface

			$c = Test::Nginx::HTTP2->new(1, socket => $client,
				pure => 1, preface => "") or return;
		}

		my $frames = $uri eq '/proxy'
			? $c->read(all => [{ length => 65535 }])
			: $c->read(all => [{ fin => 1 }]);

		if (!$extra{reuse}) {
			$c->h2_settings(0);
			$c->h2_settings(1);
		}

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{http_end} = sub {
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc' },
		]}, $sid);

		# reopen window for request body after response HEADERS is sent

		if ($uri eq '/proxy') {
			$c->h2_window(2**16, $sid);
			$c->h2_window(2**16);
			return $c->read(all => [{ sid => $sid, fin => 1 }]);
		}

		$c->h2_body('Hello world', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0', mode => 2 },
			{ name => 'grpc-message', value => '', mode => 2 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	return $f;
}

sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
