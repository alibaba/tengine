#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 backend with keepalive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket::INET;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_v2 proxy upstream_keepalive ssi rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_http_version 2;

        location / {
            proxy_pass http://backend;
        }

        location /unbuffered/ {
            proxy_pass http://backend;
            proxy_buffering off;
        }

        location /inmemory/ {
            ssi on;
            rewrite ^ /ssi.html break;
        }
    }
}

EOF

$t->write_file('ssi.html',
	'<!--#include virtual="/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(53);

###############################################################################

# There are 3 mostly independent modes of upstream operation:
#
# 1. Buffered, i.e. normal mode with "proxy_buffering on;"
# 2. Unbuffered, i.e. "proxy_buffering off;".
# 3. In memory, i.e. ssi <!--#include ... set -->
#
# These all should be tested.

my ($r, $n, $cc);

# buffered

like($r = http_get('/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/length2'), qr/X-Connection: $n.*SEE/msi, 'buffered 2');

like($r = http_get('/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/chunked2'), qr/X-Connection: $n/i,
	'buffered chunked 2');

like($r = http_get('/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/complex2'), qr/X-Connection: $n/i,
	'buffered complex chunked 2');

like($r = http_get('/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/chunk02'), qr/X-Connection: $n/i, 'buffered 0 chunk 2');

like($r = http_head('/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_head('/buffered/length/head2'), qr/X-Connection: $n/i,
	'buffered head 2');

like($r = http_get('/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/empty2'), qr/X-Connection: $n/i, 'buffered empty 2');

like($r = http_get('/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/304nolen2'), qr/X-Connection: $n/i, 'buffered 304 2');

like($r = http_get('/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/buffered/304len2'), qr/X-Connection: $n/i,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/length2'), qr/X-Connection: $n/i, 'unbuffered 2');

like($r = http_get('/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/chunked2'), qr/X-Connection: $n/i,
	'unbuffered chunked 2');

like($r = http_get('/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/complex2'), qr/X-Connection: $n/i,
	'unbuffered complex chunked 2');

like($r = http_get('/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/chunk02'), qr/X-Connection: $n/i,
	'unbuffered 0 chunk 2');

like($r = http_get('/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/empty2'), qr/X-Connection: $n/i,
	'unbuffered empty 2');

like($r = http_head('/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_head('/unbuffered/length/head2'), qr/X-Connection: $n/i,
	'unbuffered head 2');

like($r = http_get('/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/304nolen2'), qr/X-Connection: $n/i,
	'unbuffered 304 2');

like($r = http_get('/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
like(http_get('/unbuffered/304len2'), qr/X-Connection: $n/i,
	'unbuffered 304 with length 2');

# in memory

like($r = http_get('/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');

like($r = http_get('/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/empty2'), qr/200 OK/, 'inmemory empty 2');

like($r = http_get('/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');

like($r = http_get('/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');

like(http_get('/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');

# closed connection tests

like(http_get('/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

# control frame received before response is ACKed

like($r = http_get('/control1'), qr/200 OK/, 'control 1');
$r =~ m/X-Connection: (\d+)/i; $n = $1;
$r =~ m/SEE-THIS(\d+)/i; $cc = $1 + 1;
like(http_get('/control2'), qr/X-Connection: $n.*SEE-THIS$cc/msi, 'control 2');

# flow control iws:2 inherited in the next stream

like($r = http(<<EOF . '1234'), qr/1234/, 'flow 1');
GET /flow1 HTTP/1.0
Content-Length: 4

EOF
$r =~ m/X-Connection: (\d+)/i; $n = $1;
$r =~ m/SEE-THIS(\d+)/i; $cc = $1 + 1;
like(http(<<EOF . '5678'), qr/X-Connection: $n.*56_78/msi, 'flow 2');
GET /flow2 HTTP/1.0
Content-Length: 4

EOF

# check for errors, shouldn't be any

like(`grep -F '[error]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no errors');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $ccount = 0;
	my $rcount = 0;
	my $control = 0;

	# dumb server which is able to keep connections alive

	my $client;

	while ($client = $server->accept()) {
		Test::Nginx::log_core('||',
			"connection from " . $client->peerhost());
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface
		$ccount++;

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		while (1) {
			my $frames = $c->read(all => [{ fin => 4 }]);
			my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
			last unless $frame;
			my $sid = $frame->{sid};
			my $uri = $frame->{headers}{':path'};
			my $method = $frame->{headers}{':method'};
			my $more = 1 if $method ne 'HEAD';

			$rcount++;

			if ($uri =~ m/length/) {
				$c->new_stream({
					body_more => $more, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
					{ name => 'content-length',
						value => 26 },
				]}, $sid);
				$c->h2_body('TEST-OK-IF-YOU-SEE-THIS' .
					sprintf("%03d", $ccount))
					unless $method eq 'HEAD';

			} elsif ($uri =~ m/empty/) {
				$c->new_stream({ headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
					{ name => 'content-length',
						value => 0 },
				]}, $sid);

			} elsif ($uri =~ m/304nolen/) {
				$c->new_stream({ headers => [
					{ name => ':status', value => '304' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);

			} elsif ($uri =~ m/304len/) {
				$c->new_stream({ headers => [
					{ name => ':status', value => '304' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
					{ name => 'content-length',
						value => 100 },
				]}, $sid);

			} elsif ($uri =~ m/chunked/) {
				$c->new_stream({ body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);
				$c->h2_body('TEST-OK-IF-YOU-SEE-THIS' .
					sprintf("%03d", $ccount));

			} elsif ($uri =~ m/complex/) {
				$c->new_stream({ body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);

				for my $n (1..100) {
					$c->h2_body('0123456789',
						{ body_more => 1 });
					select undef, undef, undef, 0.01
						if $n % 50 == 0;
				}

				$c->h2_body('TEST-OK-IF-YOU-SEE-THIS' .
					sprintf("%03d", $ccount),
					{ body_more => 1 });
				select undef, undef, undef, 0.05;
				$c->h2_body('');

			} elsif ($uri =~ m/chunk0/) {
				$c->new_stream({ body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);
				$c->h2_body('');

			} elsif ($uri =~ m/closed/) {
				$c->new_stream({
					body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
					{ name => 'content-length',
						value => 10 },
				]}, $sid);
				$c->h2_body('0123456789');

				$c->h2_goaway(0, $sid, 0);
				last;

			} elsif ($uri =~ m/control/) {
				$c->h2_settings(0, 1 => 4096);
				$c->new_stream({
					body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);
				$c->h2_body('SEE-THIS' . $control);

				$frames = $c->read(all => [
					{ type => 'SETTINGS' }]);
				($frame) = grep { $_->{type} eq "SETTINGS" }
					@$frames;
				$control++ if $frame->{flags} eq 1;

			} elsif ($uri =~ m/flow/) {
				$c->new_stream({ body_more => 1, headers => [
					{ name => ':status', value => '200' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);
				$c->h2_settings(0, 0x4 => 2);

				$frames = $c->read(all => [{ type => 'DATA' }]);
				($frame) = grep { $_->{type} eq "DATA" }
					@$frames;

				my $data = $frame->{data};

				if ($frame->{length} == 2) {
					$c->h2_settings(0, 0x4 => 42);
					$frames = $c->read(all => [
						{ type => 'DATA' }]);
					($frame) = grep { $_->{type} eq "DATA" }
						@$frames;
					$data .= '_' . $frame->{data};
				}

				$c->h2_body($data);

			} else {
				$c->new_stream({
					body_more => 1, headers => [
					{ name => ':status', value => '404' },
					{ name => 'x-request',
						value => $rcount, mode => 2 },
					{ name => 'x-connection',
						value => $ccount, mode => 2 },
				]}, $sid);
				$c->h2_body("Oops, '$uri' not found");

				$c->h2_goaway(0, $sid, 0);
				last;
			}
		}
	}
}

###############################################################################
