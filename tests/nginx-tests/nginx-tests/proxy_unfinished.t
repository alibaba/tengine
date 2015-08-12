#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy and prematurely closed connections.  Incomplete
# responses shouldn't loose information about their incompleteness.

# In particular, incomplete responses:
#
# - shouldn't be cached
#
# - if a response is sent using chunked transfer encoding,
#   final chunk shouldn't be sent

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

my $t = Test::Nginx->new()->has(qw/http proxy cache sub shmem/)->plan(15);

$t->todo_alerts() if $^O eq 'solaris';

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=one:1m;

    server {
        listen       127.0.0.1:8080 sndbuf=32k;
        server_name  localhost;

        location / {
            sub_filter foo bar;
            sub_filter_types *;
            proxy_pass http://127.0.0.1:8081;
        }

        location /un/ {
            sub_filter foo bar;
            sub_filter_types *;
            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }

        location /cache/ {
            proxy_pass http://127.0.0.1:8081/;
            proxy_cache one;
            add_header X-Cache-Status $upstream_cache_status;
        }

        location /proxy/ {
            sub_filter foo bar;
            sub_filter_types *;
            proxy_pass http://127.0.0.1:8080/local/;
            proxy_buffer_size 1k;
            proxy_buffers 4 1k;
        }

        location /local/ {
            alias %%TESTDIR%%/;
        }
    }
}

EOF

$t->write_file('big.html', 'X' x (1024 * 1024) . 'finished');

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

http_get('/cache/length');
like(http_get('/cache/length'), qr/MISS/, 'unfinished not cached');

# chunked encoding has enough information to don't cache a response,
# much like with Content-Length available

http_get('/cache/chunked');
like(http_get('/cache/chunked'), qr/MISS/, 'unfinished chunked');

# make sure there is no final chunk in unfinished responses

like(http_get_11('/length'), qr/unfinished(?!.*\x0d\x0a?0\x0d\x0a?)/s,
	'length no final chunk');
like(http_get_11('/chunked'), qr/unfinished(?!.*\x0d\x0a?0\x0d\x0a?)/s,
	'chunked no final chunk');

# but there is final chunk in complete responses

like(http_get_11('/length/ok'), qr/finished.*\x0d\x0a?0\x0d\x0a?/s,
	'length final chunk');
like(http_get_11('/chunked/ok'), qr/finished.*\x0d\x0a?0\x0d\x0a?/s,
	'chunked final chunk');

# the same with proxy_buffering set to off

like(http_get_11('/un/length'), qr/unfinished(?!.*\x0d\x0a?0\x0d\x0a?)/s,
	'unbuffered length no final chunk');
like(http_get_11('/un/chunked'), qr/unfinished(?!.*\x0d\x0a?0\x0d\x0a?)/s,
	'unbuffered chunked no final chunk');

like(http_get_11('/un/length/ok'), qr/finished.*\x0d\x0a?0\x0d\x0a?/s,
	'unbuffered length final chunk');
like(http_get_11('/un/chunked/ok'), qr/finished.*\x0d\x0a?0\x0d\x0a?/s,
	'unbuffered chunked final chunk');

# big responses

like(http_get('/big', sleep => 0.1), qr/unfinished/s, 'big unfinished');
like(http_get('/big/ok', sleep => 0.1), qr/finished/s, 'big finished');
like(http_get('/un/big', sleep => 0.1), qr/unfinished/s, 'big unfinished un');
like(http_get('/un/big/ok', sleep => 0.1), qr/finished/s, 'big finished un');

# if disk buffering fails for some reason, there should be
# no final chunk

chmod(0000, $t->testdir() . '/proxy_temp');
like(http_get_11('/proxy/big.html', sleep => 0.5),
	qr/X(?!.*\x0d\x0a?0\x0d\x0a?)|finished/s, 'no proxy temp');

###############################################################################

sub http_get_11 {
	my ($uri, %extra) = @_;

	return http(
		"GET $uri HTTP/1.1" . CRLF .
		"Connection: close" . CRLF .
		"Host: localhost" . CRLF . CRLF,
		%extra
	);
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
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

		if ($uri eq '/length') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 100" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"unfinished" . CRLF;

		} elsif ($uri eq '/length/ok') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 10" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"finished" . CRLF;

		} elsif ($uri eq '/big') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 1000100" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF;
			for (1 .. 10000) {
				print $client ("X" x 98) . CRLF;
			}
			print $client "unfinished" . CRLF;

		} elsif ($uri eq '/big/ok') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 1000010" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF;
			for (1 .. 10000) {
				print $client ("X" x 98) . CRLF;
			}
			print $client "finished" . CRLF;

		} elsif ($uri eq '/chunked') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"ff" . CRLF .
				"unfinished" . CRLF;

		} elsif ($uri eq '/chunked/ok') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Cache-Control: max-age=300" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"a" . CRLF .
				"finished" . CRLF .
				CRLF . "0" . CRLF . CRLF;
		}
	}
}

###############################################################################
