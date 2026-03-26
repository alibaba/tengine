#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 backend returning response.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy ssi/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_cache        NAME;
        proxy_cache_key    $uri;
        proxy_cache_valid  any 1m;

        proxy_http_version 2;

        add_header X-Cache-Status $upstream_cache_status;
        add_trailer X-Stub "";

        location / {
            proxy_pass http://127.0.0.1:8081;
        }
        location /nobuf {
            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }
        location /inmemory.html {
            ssi on;
        }
    }
}

EOF

$t->write_file('inmemory.html',
	'<!--#include virtual="/ssi" set="one" --><!--#echo var="one" -->');

$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(17);

###############################################################################

like(http_get('/'), qr/\x0d\x0aSEE-THIS$/s, 'body');
like(http_get('/nobuf'), qr/\x0d\x0aSEE-THIS$/s, 'body nobuffering');
like(http_get('/inmemory.html'), qr/\x0d\x0aSEE-THIS$/s, 'body inmemory');

like(http_get('/padding'), qr/\x0d\x0aSEE-THIS$/s, 'body padding');
like(http_get('/padding/cl'), qr/\x0d\x0aSEE-THIS$/s, 'body padding length');

# incomplete or extra response body not equal to content-length;
# no cached response is expected, no final chunk for chunked response

TODO: {
local $TODO = 'not yet' if $t->read_file('nginx.conf') =~ /sendfile on/;
local $TODO = 'not yet' if $t->read_file('nginx.conf') =~ /aio (on|threads)/;

like(http_get('/less'), qr/Content-Length: 8.*SEE-$/s, 'body less cl');
like(http_get('/less'), qr/X-Cache-Status: MISS/, 'body less cl cache');
like(chunked('/less'), qr/SEE-\x0d\x0a$/, 'body less chunked');

like(http_get('/more'), qr/Content-Length: 8.*SEE-$/s, 'body more cl');
like(http_get('/more'), qr/X-Cache-Status: MISS/, 'body more cl cache');
like(chunked('/more'), qr/SEE-\x0d\x0a$/, 'body more chunked');

}

like(http_get('/nobuf/less'), qr/Content-Length: 8.*SEE-$/s, 'unbuf less cl');
like(http_get('/nobuf/less'), qr/X-Cache-Status: MISS/, 'unbuf less cl cache');
like(chunked('/nobuf/less'), qr/SEE-\x0d\x0a$/, 'unbuf less chunked');

like(http_get('/nobuf/more'), qr/Content-Length: 8.*SEE-$/s, 'unbuf more cl');
like(http_get('/nobuf/more'), qr/X-Cache-Status: MISS/, 'unbuf more cl cache');
like(chunked('/nobuf/less'), qr/SEE-\x0d\x0a$/, 'unbuf less chunked');

###############################################################################

sub chunked {
	my $uri = shift;
	http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

sub http_daemon {
	my $client;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while ($client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		my $frames = $c->read(all => [{ fin => 4 }]);
		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		my $sid = $frame->{sid};
		my $uri = $frame->{headers}{':path'};

		if ($uri eq '/padding') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS', { body_padding => 42 });

		} elsif ($uri eq '/padding/cl') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
				{ name => 'content-length', value => 8 },
			]}, $sid);
			$c->h2_body('SEE-THIS', { body_padding => 42 });

		} elsif ($uri =~ '/head') {
			$c->new_stream({ headers => [
				{ name => ':status', value => '200' },
				{ name => 'content-length', value => 8 },
			]}, $sid);

		} elsif ($uri =~ '/less') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
				{ name => 'content-length', value => 8 },
			]}, $sid);
			$c->h2_body('SEE-', { body_more => 1 });
			select undef, undef, undef, 0.2;
			$c->h2_body('');

		} elsif ($uri =~ '/more') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
				{ name => 'content-length', value => 8 },
			]}, $sid);
			$c->h2_body('SEE-', { body_more => 1 });
			select undef, undef, undef, 0.2;
			$c->h2_body('THIS-AND-THIS');

		} else {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS');

		}
	}
}

###############################################################################
