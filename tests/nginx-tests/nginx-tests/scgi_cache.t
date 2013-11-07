#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for scgi_cache.

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

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http scgi cache/)->plan(10)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    scgi_cache_path  %%TESTDIR%%/cache  keys_zone=one:1m;
    scgi_cache_key   $request_uri;

    add_header       X-Cache-Status  $upstream_cache_status;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            scgi_pass 127.0.0.1:8081;
            scgi_param SCGI 1;
            scgi_param REQUEST_URI $uri;
            scgi_cache one;
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run();

###############################################################################

like(http_get('/len'), qr/MISS/, 'length');
like(http_get('/len'), qr/HIT/, 'length cached');

like(http_get('/nolen'), qr/MISS/, 'no length');
like(http_get('/nolen'), qr/HIT/, 'no length cached');

like(http_get('/len/empty'), qr/MISS/, 'empty length');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/len/empty'), qr/HIT/, 'empty length cached');
}

like(http_get('/nolen/empty'), qr/MISS/, 'empty no length');
like(http_get('/nolen/empty'), qr/HIT/, 'empty no length cached');

like(http_get('/unfinished'), qr/MISS/, 'unfinished');
like(http_get('/unfinished'), qr/MISS/, 'unfinished not cached');

###############################################################################

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);
	my %count;

	while (my $request = $scgi->accept()) {
		$request->read_env();

		my $uri = $request->env->{REQUEST_URI} || '';
		my $c = $request->connection();

		$count{$uri} ||= 0;
		$count{$uri}++;

		if ($uri eq '/len') {
			$c->print(
				"Content-Length: 9" . CRLF .
				"Content-Type: text/html" . CRLF .
				"Cache-Control: max-age=300" . CRLF . CRLF .
				"test body"
			);

		} elsif ($uri eq '/nolen') {
			$c->print(
				"Content-Type: text/html" . CRLF .
				"Cache-Control: max-age=300" . CRLF . CRLF .
				"test body"
			);

		} elsif ($uri eq '/len/empty') {
			$c->print(
				"Content-Length: 0" . CRLF .
				"Content-Type: text/html" . CRLF .
				"Cache-Control: max-age=300" . CRLF . CRLF
			);

		} elsif ($uri eq '/nolen/empty') {
			$c->print(
				"Content-Type: text/html" . CRLF .
				"Cache-Control: max-age=300" . CRLF . CRLF
			);

		} elsif ($uri eq '/unfinished') {
			$c->print(
				"Content-Length: 10" . CRLF .
				"Content-Type: text/html" . CRLF .
				"Cache-Control: max-age=300" . CRLF . CRLF
			);
		}
	}
}

###############################################################################
