#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy with keepalive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket::INET;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy upstream_keepalive ssi rewrite/)
	->plan(49)->write_file_expand('nginx.conf', <<'EOF');

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

        proxy_http_version 1.1;
        proxy_set_header Connection "";

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
$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Can't start test backend";

###############################################################################

# There are 3 mostly independent modes of upstream operation:
#
# 1. Buffered, i.e. normal mode with "proxy_buffering on;"
# 2. Unbuffered, i.e. "proxy_buffering off;".
# 3. In memory, i.e. ssi <!--#include ... set -->
#
# These all should be tested.

my ($r, $n);

# buffered

like($r = http_get('/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');

like($r = http_get('/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');

like($r = http_get('/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');

like($r = http_get('/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');

like($r = http_head('/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');

like($r = http_get('/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/empty2'), qr/X-Connection: $n/, 'buffered empty 2');

like($r = http_get('/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');

like($r = http_get('/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');

like($r = http_get('/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');

like($r = http_get('/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');

like($r = http_get('/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');

like($r = http_get('/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/empty2'), qr/X-Connection: $n/,
	'unbuffered empty 2');

like($r = http_head('/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');

like($r = http_get('/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');

like($r = http_get('/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/304len2'), qr/X-Connection: $n/,
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

# check for errors, shouldn't be any

like(`grep -F '[error]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no errors');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $ccount = 0;
	my $rcount = 0;

	# dumb server which is able to keep connections alive

	while (my $client = $server->accept()) {
		Test::Nginx::log_core('||',
			"connection from " . $client->peerhost());
		$client->autoflush(1);
		$ccount++;

		while (1) {
			my $headers = '';
			my $uri = '';

			while (<$client>) {
				Test::Nginx::log_core('||', $_);
				$headers .= $_;
				last if (/^\x0d?\x0a?$/);
			}

			last if $headers eq '';
			$rcount++;

			$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

			if ($uri =~ m/length/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 26" . CRLF . CRLF;
				print $client "TEST-OK-IF-YOU-SEE-THIS" .
					sprintf("%03d", $ccount)
					unless $headers =~ /^HEAD/i;

			} elsif ($uri =~ m/empty/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 0" . CRLF . CRLF;

			} elsif ($uri =~ m/304nolen/) {
				print $client
					"HTTP/1.1 304 Not Modified" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF . CRLF;

			} elsif ($uri =~ m/304len/) {
				print $client
					"HTTP/1.1 304 Not Modified" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 100" . CRLF . CRLF;

			} elsif ($uri =~ m/chunked/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;
				print $client
					"1a" . CRLF .
					"TEST-OK-IF-YOU-SEE-THIS" .
					sprintf("%03d", $ccount) . CRLF .
					"0" . CRLF . CRLF
					unless $headers =~ /^HEAD/i;

			} elsif ($uri =~ m/complex/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;

				if ($headers !~ /^HEAD/i) {
					for my $n (1..100) {
						print $client
							"a" . CRLF .
							"0123456789" . CRLF;
						select undef, undef, undef, 0.01
							if $n % 50 == 0;
					}
					print $client
						"1a" . CRLF .
						"TEST-OK-IF-YOU-SEE-THIS" .
						sprintf("%03d", $ccount) .
						CRLF .
						"0" . CRLF;
					select undef, undef, undef, 0.05;
					print $client CRLF;
				}

			} elsif ($uri =~ m/chunk0/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;
				print $client
					"0" . CRLF . CRLF
					unless $headers =~ /^HEAD/i;

			} elsif ($uri =~ m/closed/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Connection: close" . CRLF .
					"Content-Length: 12" . CRLF . CRLF .
					"0123456789" . CRLF;
				last;

			} else {
				print $client
					"HTTP/1.1 404 Not Found" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Connection: close" . CRLF . CRLF .
					"Oops, '$uri' not found" . CRLF;
				last;
			}
		}

		close $client;
	}
}

###############################################################################
