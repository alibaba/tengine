#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for HTTP/2 extensible prioritization, RFC 9218.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ SOL_SOCKET SO_RCVBUF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 mirror proxy rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    http2 on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        large_client_header_buffers 4 32k;

        location / { }

        location /merge/ {
            proxy_pass http://127.0.0.1:8081/;
            add_header X-Upstream-Priority $upstream_http_priority;
        }

        location /subrequest/ {
            mirror /mirror;
            alias %%TESTDIR%%/;
        }

        location /mirror {
            internal;
            proxy_pass http://127.0.0.1:8081/urgency;
        }
    }

    server {
        listen       127.0.0.1:8082 sndbuf=4k;
        server_name  localhost;

        location / { }

        location /trailers/ {
            alias %%TESTDIR%%/;
            output_buffers 1 1m;
            add_trailer X-Trailer foo;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /urgency {
            add_header Priority "u=0";
            return 200 "SEE-THIS";
        }

        location /incremental {
            add_header Priority "i";
            return 200 "SEE-THIS";
        }

        location /malformed {
            add_header Priority "u=0, @bad";
            return 200 "SEE-THIS";
        }
    }
}

EOF

# file size is slightly beyond initial window size: 2**16 + 80 bytes

$t->write_file('t1.html',
	join('', map { sprintf "X%04dXXX", $_ } (1 .. 8202)));

$t->write_file('t2.html', 'SEE-THIS');
$t->write_file('t3.html', 'x' x 2**17);
$t->write_file('t4.html', 'x' x 2**18);

$t->run()->plan(62);

###############################################################################

my $s = Test::Nginx::HTTP2->new(undef, pure => 1);
my $frames = $s->read(all => [{ type => 'SETTINGS' }]);
my ($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;

SKIP: {
skip 'RFC 9218 priorities not signalled', 62 unless $frame->{9};

is($frame->{9}, 1, 'SETTINGS_NO_RFC7540_PRIORITIES');

# order() signals both streams and returns their DATA order. These four are
# the control: below, a field wrongly ignored looks like one correctly ignored

is(order('u=3', 'u=0'), '3 1', 'urgency');
is(order('u=0', 'u=3'), '1 3', 'urgency - vice versa');
is(order('u=3, i', 'u=3'), '3 1', 'incremental');
is(order('u=3', 'u=3'), '1 3', 'equal priority');

# 4.  Priority Parameters
#   Where the Dictionary is successfully parsed ... unknown priority
#   parameters, priority parameters with out-of-range values, or values
#   of unexpected types MUST be ignored.

is(order('u=2', 'u=9'), '1 3', 'urgency out of range');

# these parse, but the urgency is not a dictionary member

is(order('u=3', 'a=1;u=0'), '1 3', 'parameter is not a member');
is(order('u=3', 'x="a,u=0"'), '1 3', 'comma in quoted string');
is(order('u=3', 'u=0, u=9'), '1 3', 'duplicate key');

# RFC 8941, 4.2.  Parsing Structured Fields
#   If parsing fails the entire field value MUST be ignored.

is(order('u=3', 'U=0'), '1 3', 'uppercase key');
is(order('u=3', 'u=0, @bad'), '1 3', 'bad item');
is(order('u=3', 'u=0, x=1234567890123456'), '1 3', 'integer too long');
is(order('u=3', 'u=0, x="unterminated'), '1 3', 'unterminated string');
is(order('u=3', 'u=0, x=1.2345'), '1 3', 'fraction too long');
is(order('u=3', 'u=0, x=1234567890123.5'), '1 3', 'integer part too long');
is(order('u=3', 'u=0, x=1.'), '1 3', 'decimal without fraction');
is(order('u=3', 'u=0,'), '1 3', 'trailing separator');
is(order('u=3', 'u=0 i'), '1 3', 'missing separator');
is(order('u=3', 'u=0, i;'), '1 3', 'parameter without key');
is(order('u=3', 'u=0, x=:a:'), '1 3', 'invalid base64');

# individual items are bounded so that parse time stays proportional to a
# well-formed field

is(order('u=3', 'u=0, x="' . ('a' x 1025) . '"'), '1 3', 'string too long');
is(order('u=3', 'u=0, x=' . ('a' x 513)), '1 3', 'token too long');
is(order('u=3', join ', ', 'u=0', map { "x$_=1" } (1 .. 1024)), '1 3',
	'too many members');

# RFC 8941 requires 16384 octets after decoding, that is 21848 characters
# 21849 does not decode

is(order('u=3', 'u=0, x=:' . ('A' x 21848) . ':'), '3 1',
	'byte sequence at the RFC minimum');
is(order('u=3', 'u=0, x=:' . ('A' x 21850) . ':'), '1 3',
	'byte sequence over the limit');

# every bare item type has to parse before "u=0" can be used

is(order('u=3', 'u=0, x=abc'), '3 1', 'token');
is(order('u=3', 'u=0, x=:aGk=:'), '3 1', 'byte sequence');
is(order('u=3', 'u=0, x=(1 2)'), '3 1', 'inner list');
is(order('u=3', 'u=0, x=1.5'), '3 1', 'decimal');
is(order('u=3', 'u=0, x=-1'), '3 1', 'negative integer');
is(order('u=3', 'u=0, x=1;a=2'), '3 1', 'item parameter');
is(order('u=3', 'u=0, i=?0'), '3 1', 'boolean');
is(order('u=3', 'u=0 , i'), '3 1', 'optional whitespace');
is(order('u=3', 'u=0, x="a\"b"'), '3 1', 'escaped quote');
is(order('u=3', ['u=0', 'i']), '3 1', 'combined field lines');

# PRIORITY_UPDATE

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_priority_update(3, 'u=0');

is(data_order($s), '3 1', 'open stream');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(1, 'u=7');

is(data_order(stalled($s)), '3 1', 'before HEADERS');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(3, 'u=7');

is(data_order(stalled($s, 'u=3', 'u=0')), '1 3', 'overrides header');

# a frame carries a complete set: an extension-only value resets urgency

$s = stalled(Test::Nginx::HTTP2->new(), 'u=3', 'u=0');
$s->h2_priority_update(3, 'a=1');

is(data_order($s), '1 3', 'complete set');

# a value that does not parse leaves the priority alone

$s = stalled(Test::Nginx::HTTP2->new(), 'u=7');
$s->h2_priority_update(1, 'U=0');

is(data_order($s), '3 1', 'malformed value');

# a header value cannot carry leading space, a frame value can

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_priority_update(3, ' u=0');

is(data_order($s), '3 1', 'leading space');

# a split frame is reassembled, one over the state buffer is skipped

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_priority_update(3, 'u=0', split => [11]);

is(data_order($s), '3 1', 'split');

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_priority_update(3, 'u=0, xxxxxxxxxxxxxxxxxxxxxx=1', split => [11]);

is(data_order($s), '1 3', 'split over state buffer');

# prioritized idle streams reuse the closed node budget: the 33rd evicts
# the first, and the signal it carried is lost

is(buffered(31), '3 1', 'buffered priority - 32 idle streams');
is(buffered(32), '1 3', 'buffered priority - 33 idle streams');

# trailers are queued along with the stream data, they must not hold back
# a more urgent stream queued later while the client is not reading;
# WSASend() accepts any amount of data

SKIP: {
skip 'win32', 3 if $^O eq 'MSWin32';

$s = Test::Nginx::HTTP2->new(port(8082));
$s->{socket}->setsockopt(SOL_SOCKET, SO_RCVBUF, 16384) or die $!;
$s->h2_settings(0, 0x4 => 2**24);
$s->h2_window(2**24);

$s->new_stream(request('/trailers/t3.html', 'u=7'));
$s->read(all => [{ sid => 1, fin => 0x4 }]);

$s->new_stream(request('/t2.html', 'u=0'));
$frames = $s->read(all => [{ sid => 1, fin => 1 }, { sid => 3, fin => 1 }]);

my @order = map { "$_->{type}:$_->{sid}" }
	grep { $_->{type} =~ /HEADERS|DATA/ && $_->{flags} & 1 } @$frames;

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.9');

is("@order", 'DATA:3 HEADERS:1', 'trailers');

}

# unsent trailers of a reset stream are discarded and not credited to the
# connection window: the window fits the response with trailers, a larger
# one then consumes exactly what is left of it

$s = Test::Nginx::HTTP2->new(port(8082));
$s->{socket}->setsockopt(SOL_SOCKET, SO_RCVBUF, 16384) or die $!;
$s->h2_settings(0, 0x4 => 2**24);
$s->h2_window(2**17);

$s->new_stream(request('/trailers/t3.html'));
$s->read(all => [{ sid => 1, fin => 0x4 }]);
$s->h2_rst(1, 8);

$s->new_stream(request('/t4.html'));
$frames = $s->read(all => [{ sid => 3, fin => 1 }], wait => 0.5);

my $len = 0;
$len += $_->{length} for grep { $_->{type} eq 'DATA' } @$frames;

is($len, 2**16 - 1 + 2**17, 'trailers - reset stream window');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.9');

is(grep({ $_->{type} eq 'HEADERS' && $_->{sid} == 1 } @$frames), 0,
	'trailers - reset stream');

}

}

# RFC 7540 signals no longer reorder anything

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_priority(0, 1);
$s->h2_priority(255, 3);

is(data_order($s), '1 3', 'PRIORITY frames ignored');

$s = stalled(Test::Nginx::HTTP2->new());
$s->h2_settings(0, 0x9 => 1);

is(data_order($s), '1 3', 'SETTINGS_NO_RFC7540_PRIORITIES from client');

# the merge affects scheduling only, the forwarded field stays the origin's,
# a parameter present in the response overrides the client's, absent leaves it

$s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream(request('/merge/urgency'));
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;

is($frame->{headers}{'priority'}, 'u=0', 'upstream Priority forwarded');
is($frame->{headers}{'x-upstream-priority'}, 'u=0',
	'upstream Priority - variable');

is(order('u=3', 'u=7', '/merge/urgency'), '3 1', 'upstream Priority - urgency');
is(order('u=3', 'u=0', '/merge/incremental'), '3 1',
	'upstream Priority - client urgency kept');
is(order('u=3', 'u=7', '/merge/malformed'), '1 3',
	'upstream Priority - malformed');

like(http_get('/merge/urgency'), qr/Priority: u=0/,
	'upstream Priority - HTTP/1 client');

# a subrequest shares the stream, so a Priority it receives must not
# reprioritize the response the client is waiting for

is(order('u=3', 'u=3', '/subrequest/t2.html'), '1 3',
	'upstream Priority - subrequest');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(1, 'u=0', sid => 1);

is(goaway($s), 1, 'non-zero stream - PROTOCOL_ERROR');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(0, 'u=0');

is(goaway($s), 1, 'stream 0 - PROTOCOL_ERROR');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(2, 'u=0');

is(goaway($s), 1, 'even stream - PROTOCOL_ERROR');

$s = Test::Nginx::HTTP2->new();
$s->h2_priority_update(1, 'u=0', len => 3);

is(goaway($s), 6, 'short payload - FRAME_SIZE_ERROR');

$s = Test::Nginx::HTTP2->new();
$s->h2_settings(0, 0x9 => 2);

is(goaway($s), 1, 'SETTINGS bad value - PROTOCOL_ERROR');

}

###############################################################################

# stream 1 requests a file slightly larger than the connection window and
# stalls on it, stream 3 stalls behind it

sub stalled {
	my ($s, $p1, $p2, $path) = @_;

	$path = '/t2.html' unless defined $path;

	$s->new_stream(request('/t1.html', $p1));
	$s->read(all => [{ sid => 1, length => 2**16 - 1 }]);

	$s->new_stream(request($path, $p2));
	$s->read(all => [{ sid => 3, fin => 0x4 }]);

	return $s;
}

sub data_order {
	my ($s) = @_;

	$s->h2_window(2**17, 1);
	$s->h2_window(2**17, 3);
	$s->h2_window(2**17);

	my $frames = $s->read(all => [
		{ sid => 1, fin => 1 },
		{ sid => 3, fin => 1 }
	]);

	return join ' ', map { $_->{sid} }
		grep { $_->{type} eq 'DATA' } @$frames;
}

sub order {
	return data_order(stalled(Test::Nginx::HTTP2->new(), @_));
}

# prioritize stream 1 before it exists, behind $extra other idle streams

sub buffered {
	my ($extra) = @_;

	my $s = Test::Nginx::HTTP2->new();

	$s->h2_priority_update(1, 'u=7');
	$s->h2_priority_update(2 * $_ + 101, 'u=4') for (1 .. $extra);

	return data_order(stalled($s));
}

# $priority is one Priority field line, a reference to a list of them, or undef

sub request {
	my ($path, $priority) = @_;

	my @lines = !defined $priority ? ()
		: ref $priority ? @$priority : ($priority);

	return { headers => [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => $path, mode => 1 },
		{ name => ':authority', value => 'localhost', mode => 1 },
		map { { name => 'priority', value => $_, mode => 2 } } @lines ] };
}

sub goaway {
	my ($s) = @_;

	my $frames = $s->read(all => [{ type => 'GOAWAY' }]);
	my ($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;

	return $frame->{code};
}

###############################################################################
