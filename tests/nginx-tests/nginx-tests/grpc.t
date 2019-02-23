#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for grpc backend.

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

my $t = Test::Nginx->new()->has(qw/http rewrite http_v2 grpc/)
	->has(qw/upstream_keepalive/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        http2_max_field_size 128k;
        http2_max_header_size 128k;
        http2_body_preread_size 128k;

        location / {
            grpc_pass grpc://127.0.0.1:8081;

            if ($arg_if) {
                # nothing
            }

            limit_except GET {
                # nothing
            }
        }

        location /KeepAlive {
            grpc_pass u;
        }

        location /LongHeader {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header X-LongHeader $arg_h;
        }

        location /LongField {
            grpc_pass 127.0.0.1:8081;
            grpc_buffer_size 65k;
        }

        location /SetHost {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header Host custom;
        }

        location /SetArgs {
            grpc_pass 127.0.0.1:8081;
            set $args $arg_c;
        }
    }
}

EOF

$t->try_run('no grpc')->plan(100);

###############################################################################

my $p = port(8081);
my $f = grpc();

my $frames = $f->{http_start}('/SayHello');
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'request - HEADERS flags');
ok((my $sid = $frame->{sid}) % 2, 'request - HEADERS sid odd');
is($frame->{headers}{':method'}, 'POST', 'request - method');
is($frame->{headers}{':scheme'}, 'http', 'request - scheme');
is($frame->{headers}{':path'}, '/SayHello', 'request - path');
is($frame->{headers}{':authority'}, "127.0.0.1:$p", 'request - authority');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'request - content type');
is($frame->{headers}{te}, 'trailers', 'request - te');

$frames = $f->{data}('Hello');
($frame) = grep { $_->{type} eq "SETTINGS" } @$frames;
is($frame->{flags}, 1, 'request - SETTINGS ack');
is($frame->{sid}, 0, 'request - SETTINGS sid');
is($frame->{length}, 0, 'request - SETTINGS length');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello', 'request - DATA');
is($frame->{length}, 5, 'request - DATA length');
is($frame->{flags}, 1, 'request - DATA flags');
is($frame->{sid}, $sid, 'request - DATA sid match');

$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'response - HEADERS flags');
is($frame->{sid}, 1, 'response - HEADERS sid');
is($frame->{headers}{':status'}, '200', 'response - status');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'response - content type');
ok($frame->{headers}{server}, 'response - server');
ok($frame->{headers}{date}, 'response - date');
ok(my $c = $frame->{headers}{'x-connection'}, 'response - connection');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello world', 'response - DATA');
is($frame->{length}, 11, 'response - DATA length');
is($frame->{flags}, 0, 'response - DATA flags');
is($frame->{sid}, 1, 'response - DATA sid');

(undef, $frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 5, 'response - trailers flags');
is($frame->{sid}, 1, 'response - trailers sid');
is($frame->{headers}{'grpc-message'}, '', 'response - trailers message');
is($frame->{headers}{'grpc-status'}, '0', 'response - trailers status');

# next request is on a new backend connection, no sid incremented

$frames = $f->{http_start}('/SayHello');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{sid}, $sid, 'request 2 - HEADERS sid again');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
cmp_ok($frame->{headers}{'x-connection'}, '>', $c, 'response 2 - connection');

# upstream keepalive

$frames = $f->{http_start}('/KeepAlive');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{sid}, $sid, 'keepalive - HEADERS sid');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($c = $frame->{headers}{'x-connection'}, 'keepalive - connection');

$frames = $f->{http_start}('/KeepAlive', reuse => 1);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
cmp_ok($frame->{sid}, '>', $sid, 'keepalive - HEADERS sid next');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{'x-connection'}, $c, 'keepalive - connection reuse');

# various header compression formats

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(mode => 3);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'without indexing');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'without indexing 2');

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(mode => 4);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'without indexing new');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'without indexing new 2');

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(mode => 5);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'never indexed');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'never indexed 2');

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(mode => 6);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'never indexed new');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'never indexed new 2');

# padding & priority

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(padding => 7);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'padding');

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(prio => 137, dep => 0x01020304);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'priority');

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(padding => 7, prio => 137, dep => 0x01020304);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'padding priority');

SKIP: {
skip 'long test', 1 unless $ENV{TEST_NGINX_UNSAFE};

$f->{http_start}('/SaySplit');
$f->{data}('Hello');
$frames = $f->{http_end}(padding => 7, prio => 137, dep => 0x01020304,
	split => [(map{1}(1..20)), 30], split_delay => 0.1);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'padding priority split');

}

# grpc error, no empty data frame expected

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_err}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 5, 'grpc error - HEADERS flags');
($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok(!$frame, 'grpc error - no DATA frame');

# continuation from backend, expect parts assembled

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{continuation}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'continuation - HEADERS flags');
is($frame->{headers}{':status'}, '200', 'continuation - status');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'continuation - content type');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello world', 'continuation - DATA');
is($frame->{length}, 11, 'continuation - DATA length');
is($frame->{flags}, 0, 'continuation - DATA flags');

(undef, $frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 5, 'continuation - trailers flags');
is($frame->{headers}{'grpc-message'}, '', 'continuation - trailers message');
is($frame->{headers}{'grpc-status'}, '0', 'continuation - trailers status');

# continuation from backend, header split

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}(mode => 6, continuation => [map { 1 } (1 .. 42)]);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':status'}, '200', 'continuation - header split');

# continuation to backend

$frames = $f->{http_start}('/LongHeader?h=' . ('Z' x 31337));
@$frames = grep { $_->{type} =~ "HEADERS|CONTINUATION" } @$frames;
is(@$frames, 4, 'continuation - frames');

$frame = shift @$frames;
is($frame->{type}, 'HEADERS', 'continuation - HEADERS');
is($frame->{length}, 16384, 'continuation - HEADERS length');
is($frame->{flags}, 1, 'continuation - HEADERS flags');
ok($frame->{sid}, 'continuation - HEADERS sid');

$frame = shift @$frames;
is($frame->{type}, 'CONTINUATION', 'continuation - CONTINUATION');
is($frame->{length}, 16384, 'continuation - CONTINUATION length');
is($frame->{flags}, 0, 'continuation - CONTINUATION flags');
ok($frame->{sid}, 'continuation - CONTINUATION sid');

$frame = shift @$frames;
is($frame->{type}, 'CONTINUATION', 'continuation - CONTINUATION 2');
is($frame->{length}, 16384, 'continuation - CONTINUATION 2 length');
is($frame->{flags}, 0, 'continuation - CONTINUATION 2 flags');

$frame = shift @$frames;
is($frame->{type}, 'CONTINUATION', 'continuation - CONTINUATION n');
cmp_ok($frame->{length}, '<', 16384, 'continuation - CONTINUATION n length');
is($frame->{flags}, 4, 'continuation - CONTINUATION n flags');
is($frame->{headers}{':path'}, '/LongHeader?h=' . 'Z' x 31337,
	'continuation - path');
is($frame->{headers}{'x-longheader'}, 'Z' x 31337, 'continuation - header');

$f->{http_end}();

# long header field

$f->{http_start}('/LongField');
$f->{data}('Hello');
$frames = $f->{field_len}(2**7);
($frame) = grep { $_->{flags} & 0x4 } @$frames;
is($frame->{headers}{'x' x 2**7}, 'y' x 2**7, 'long header field 1');

$f->{http_start}('/LongField');
$f->{data}('Hello');
$frames = $f->{field_len}(2**8);
($frame) = grep { $_->{flags} & 0x4 } @$frames;
is($frame->{headers}{'x' x 2**8}, 'y' x 2**8, 'long header field 2');

$f->{http_start}('/LongField');
$f->{data}('Hello');
$frames = $f->{field_len}(2**15);
($frame) = grep { $_->{flags} & 0x4 } @$frames;
is($frame->{headers}{'x' x 2**15}, 'y' x 2**15, 'long header field 3');

# flow control

$f->{http_start}('/FlowControl');
$frames = $f->{data_len}(('Hello' x 13000) . ('x' x 550), 65535);
my $sum = eval join '+', map { $_->{type} eq "DATA" && $_->{length} } @$frames;
is($sum, 65535, 'flow control - iws length');

$f->{update}(10);
$f->{update_sid}(10);

$frames = $f->{data_len}(undef, 10);
($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, 10, 'flow control - update length');
is($frame->{flags}, 0, 'flow control - update flags');

$f->{update_sid}(10);
$f->{update}(10);

$frames = $f->{data_len}(undef, 5);
($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, 5, 'flow control - rest length');
is($frame->{flags}, 1, 'flow control - rest flags');

$f->{http_end}();

# preserve output

$f->{http_start}('/Preserve');
$f->{data}('Hello');
$frames = $f->{http_pres}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'preserve - HEADERS');

my @data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 20480, 'preserve - DATA');

(undef, $frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 5, 'preserve - trailers');

# DATA padding

$f->{http_start}('/SayPadding');
$f->{data}('Hello');
$frames = $f->{http_end}(body_padding => 42);
($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello world', 'response - DATA');
is($frame->{length}, 11, 'response - DATA length');
is($frame->{flags}, 0, 'response - DATA flags');

# :authority inheritance

$frames = $f->{http_start}('/SayHello?if=1');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':authority'}, "127.0.0.1:$p", 'authority in if');
$f->{data}('Hello');
$f->{http_end}();

# misc tests

$frames = $f->{http_start}('/SetHost');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok(!$frame->{headers}{':authority'}, 'set host - authority');
is($frame->{headers}{'host'}, 'custom', 'set host - host');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/SetArgs?f');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':path'}, '/SetArgs', 'set args');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/SetArgs?c=1');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':path'}, '/SetArgs?1', 'set args len');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/SetArgs esc');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':path'}, '/SetArgs%20esc', 'uri escape');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':path'}, '/', 'root index');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/', method => 'GET');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':method'}, 'GET', 'method get');
$f->{data}('Hello');
$f->{http_end}();

$frames = $f->{http_start}('/', method => 'HEAD');
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{':method'}, 'HEAD', 'method head');
$f->{data}('Hello');
$f->{http_end}();

###############################################################################

sub grpc {
	my ($server, $client, $f, $s, $c, $sid, $csid, $uri);
	my $n = 0;

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
		my $body_more = 1 if $uri !~ /LongHeader/;
		my $meth = $extra{method} || 'POST';
		$s = Test::Nginx::HTTP2->new() if !defined $s;
		$csid = $s->new_stream({ body_more => $body_more, headers => [
			{ name => ':method', value => $meth, mode => !!$meth },
			{ name => ':scheme', value => 'http', mode => 0 },
			{ name => ':path', value => $uri, },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-type', value => 'application/grpc' },
			{ name => 'te', value => 'trailers', mode => 2 }]});

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
			$n++;

			$client->sysread(my $buf, 24) == 24 or return; # preface

			$c = Test::Nginx::HTTP2->new(1, socket => $client,
				pure => 1, preface => "") or return;
		}

		my $frames = $c->read(all => [{ fin => 4 }]);

		if (!$extra{reuse}) {
			$c->h2_settings(0);
			$c->h2_settings(1);
		}

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{data} = sub {
		my ($body, %extra) = @_;
		$s->h2_body($body, { %extra });
		return $c->read(all => [{ sid => $sid,
			length => length($body) }]);
	};
	$f->{data_len} = sub {
		my ($body, $len) = @_;
		$s->h2_body($body) if defined $body;
		return $c->read(all => [{ sid => $sid, length => $len }]);
	};
	$f->{update} = sub {
		$c->h2_window(shift);
	};
	$f->{update_sid} = sub {
		$c->h2_window(shift, $sid);
	};
	$f->{http_end} = sub {
		my (%extra) = @_;
		$c->new_stream({ body_more => 1, %extra, headers => [
			{ name => ':status', value => '200',
				mode => $extra{mode} || 0 },
			{ name => 'content-type', value => 'application/grpc',
				mode => $extra{mode} || 1, huff => 1 },
			{ name => 'x-connection', value => $n,
				mode => 2, huff => 1 },
		]}, $sid);
		$c->h2_body('Hello world', { body_more => 1,
			body_padding => $extra{body_padding} });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0',
				mode => 2, huff => 1 },
			{ name => 'grpc-message', value => '',
				mode => 2, huff => 1 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	$f->{http_pres} = sub {
		my (%extra) = @_;
		$s->h2_settings(0, 0x4 => 8192);
		$c->new_stream({ body_more => 1, %extra, headers => [
			{ name => ':status', value => '200',
				mode => $extra{mode} || 0 },
			{ name => 'content-type', value => 'application/grpc',
				mode => $extra{mode} || 1, huff => 1 },
			{ name => 'x-connection', value => $n,
				mode => 2, huff => 1 },
		]}, $sid);
		for (1 .. 20) {
			$c->h2_body(sprintf('Hello %02d', $_) x 128, {
				body_more => 1,
				body_padding => $extra{body_padding} });
			$c->h2_ping("PING");
		}
		# reopen window
		$s->h2_window(2**24);
		$s->h2_window(2**24, $csid);
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0',
				mode => 2, huff => 1 },
			{ name => 'grpc-message', value => '',
				mode => 2, huff => 1 },
		]}, $sid);

		return $s->read(all => [{ sid => $csid, fin => 1 }]);
	};
	$f->{http_err} = sub {
		$c->new_stream({ headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc',
				mode => 1, huff => 1 },
			{ name => 'grpc-status', value => '12',
				mode => 2, huff => 1 },
			{ name => 'grpc-message', value => 'unknown service',
				mode => 2, huff => 1 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	$f->{continuation} = sub {
		$c->new_stream({ continuation => 1, body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
		]}, $sid);
		$c->h2_continue($sid, { continuation => 1, headers => [
			{ name => 'content-type', value => 'application/grpc',
				mode => 1, huff => 1 },
		]});
		$c->h2_continue($sid, { headers => [
			# an empty CONTINUATION frame is legitimate
		]});
		$c->h2_body('Hello world', { body_more => 1 });
		$c->new_stream({ continuation => 1, headers => [
			{ name => 'grpc-status', value => '0',
				mode => 2, huff => 1 },
		]}, $sid);
		$c->h2_continue($sid, { headers => [
			{ name => 'grpc-message', value => '',
				mode => 2, huff => 1 },
		]});

		return $s->read(all => [{ fin => 1 }]);
	};
	$f->{field_len} = sub {
		my ($len) = @_;
		$c->new_stream({ continuation => [map {2**14} (0..$len/2**13)],
			body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc',
				mode => 1, huff => 1 },
			{ name => 'x' x $len, value => 'y' x $len, mode => 6 },
		]}, $sid);
		$c->h2_body('Hello world', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0',
				mode => 2, huff => 1 },
			{ name => 'grpc-message', value => '',
				mode => 2, huff => 1 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	return $f;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
