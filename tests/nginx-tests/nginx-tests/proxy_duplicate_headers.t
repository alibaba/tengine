#!/usr/bin/perl

# (C) Maxim Dounin

# Test for http backend returning response with invalid and duplicate
# headers.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

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
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/200 OK/, 'normal');

like(http_get('/invalid-length'), qr/502 Bad/, 'invalid length');
like(http_get('/duplicate-length'), qr/502 Bad/, 'duplicate length');
like(http_get('/unknown-transfer-encoding'), qr/502 Bad/,
	'unknown transfer encoding');
like(http_get('/duplicate-transfer-encoding'), qr/502 Bad/,
	'duplicate transfer encoding');
like(http_get('/length-and-transfer-encoding'), qr/502 Bad/,
	'length and transfer encoding');
like(http_get('/transfer-encoding-and-length'), qr/502 Bad/,
	'transfer encoding and length');

like(http_get('/duplicate-expires'), qr/Expires: foo(?!.*bar)/s,
	'duplicate expires ignored');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Content-Length: 0' . CRLF . CRLF;

		} elsif ($uri eq '/invalid-length') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Content-Length: foo' . CRLF . CRLF;

		} elsif ($uri eq '/duplicate-length') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Content-Length: 0' . CRLF .
				'Content-Length: 0' . CRLF . CRLF;

		} elsif ($uri eq '/unknown-transfer-encoding') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Transfer-Encoding: foo' . CRLF . CRLF;

		} elsif ($uri eq '/duplicate-transfer-encoding') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Transfer-Encoding: chunked' . CRLF .
				'Transfer-Encoding: chunked' . CRLF . CRLF .
				'0' . CRLF . CRLF;

		} elsif ($uri eq '/length-and-transfer-encoding') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Content-Length: 0' . CRLF .
				'Transfer-Encoding: chunked' . CRLF . CRLF .
				'0' . CRLF . CRLF;

		} elsif ($uri eq '/transfer-encoding-and-length') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Transfer-Encoding: chunked' . CRLF .
				'Content-Length: 0' . CRLF . CRLF .
				'0' . CRLF . CRLF;

		} elsif ($uri eq '/duplicate-expires') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF .
				'Expires: foo' . CRLF .
				'Expires: bar' . CRLF . CRLF;

		}

		close $client;
	}
}

###############################################################################
