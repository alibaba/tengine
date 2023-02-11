#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for http backend with extra data.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http proxy cache rewrite addition/)->plan(22)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path cache keys_zone=one:1m;
    proxy_cache_key $request_uri;
    proxy_cache_valid any 1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
            add_after_body /after;
        }

        location /unbuf/ {
            proxy_pass http://127.0.0.1:8081;
            proxy_buffering off;
            add_after_body /after;
        }

        location /head/ {
            proxy_pass http://127.0.0.1:8081;
            proxy_cache one;
            add_after_body /after;
        }

        location /after {
            return 200 ":after\n";
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/SEE-THIS(?!-BUT-NOT-THIS)/, 'response with extra data');
like(http_get('/short'), qr/SEE-THIS(?!.*:after)/s, 'too short response');
like(http_get('/empty'), qr/200 OK(?!.*:after)/s, 'empty too short response');

like(http_head('/'), qr/200 OK(?!.*SEE-THIS)/s, 'no data in HEAD');
like(http_head('/short'), qr/200 OK(?!.*SEE-THIS)/s, 'too short to HEAD');
like(http_head('/empty'), qr/200 OK/, 'empty response to HEAD');

# unbuffered responses

like(http_get('/unbuf/'), qr/SEE-THIS(?!-BUT-NOT-THIS)/,
	'unbuffered with extra data');
like(http_get('/unbuf/short'), qr/SEE-THIS(?!.*:after)/s,
	'unbuffered too short response');
like(http_get('/unbuf/empty'), qr/200 OK(?!.*:after)/s,
	'unbuffered empty too short response');

like(http_head('/unbuf/'), qr/200 OK(?!.*SEE-THIS)/s,
	'unbuffered no data in HEAD');
like(http_head('/unbuf/short'), qr/200 OK(?!.*SEE-THIS)/s,
	'unbuffered too short response to HEAD');
like(http_head('/unbuf/empty'), qr/200 OK/,
	'unbuffered empty response to HEAD');

# caching of responsses to HEAD requests

like(http_head('/head/empty'), qr/200 OK(?!.*SEE-THIS)/s, 'head no body');
like(http_head('/head/matching'), qr/200 OK(?!.*SEE-THIS)/s, 'head matching');
like(http_head('/head/extra'), qr/200 OK(?!.*SEE-THIS)/s, 'head extra');
like(http_head('/head/short'), qr/200 OK(?!.*SEE-THIS)/s, 'head too short');

like(http_get('/head/empty'), qr/SEE-THIS/, 'head no body cached');
like(http_get('/head/matching'), qr/SEE-THIS/, 'head matching cached');
like(http_get('/head/extra'), qr/SEE-THIS(?!-BUT-NOT-THIS)/s,
	'head extra cached');
like(http_get('/head/short'), qr/SEE-THIS(?!.*:after)/s,
	'head too short cached');

# "zero size buf" alerts (ticket #2117)

like(http_get('/zero'), qr/200 OK(?!.*NOT-THIS)/s, 'zero size');
like(http_get('/unbuf/zero'), qr/200 OK(?!.*NOT-THIS)/s,
	'unbuffered zero size');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	my ($uri, $head);

	while (my $c = $server->accept()) {
		$c->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$c>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
		$uri =~ s!^/unbuf!!;

		$head = ($headers =~ /^HEAD/);

		if ($uri eq '/') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS-BUT-NOT-THIS\n");

		} elsif ($uri eq '/zero') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 0\n\n");
			$c->print("NOT-THIS\n");

		} elsif ($uri eq '/short') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");
			$c->print("SEE-THIS-TOO-SHORT-RESPONSE\n");

		} elsif ($uri eq '/empty') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");

		} elsif ($uri eq '/head/empty') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS") unless $head;

		} elsif ($uri eq '/head/matching') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS");

		} elsif ($uri eq '/head/extra') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS-BUT-NOT-THIS\n");

		} elsif ($uri eq '/head/short') {
			$c->print("HTTP/1.1 200 OK\n");
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");
			$c->print("SEE-THIS\n");
		}

		close $c;
	}
}

###############################################################################
