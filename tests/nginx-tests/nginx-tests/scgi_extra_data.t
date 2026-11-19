#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Test for scgi backend with extra data.

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

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()
	->has(qw/http scgi cache rewrite addition/)->plan(22)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    scgi_param SCGI 1;
    scgi_param REQUEST_URI $request_uri;
    scgi_param REQUEST_METHOD $request_method;

    scgi_cache_path cache keys_zone=one:1m;
    scgi_cache_key $request_uri;
    scgi_cache_valid any 1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            scgi_pass 127.0.0.1:8081;
            add_after_body /after;
        }

        location /unbuf/ {
            scgi_pass 127.0.0.1:8081;
            scgi_buffering off;
            add_after_body /after;
        }

        location /head/ {
            scgi_pass 127.0.0.1:8081;
            scgi_cache one;
            add_after_body /after;
        }

        location /after {
            return 200 ":after\n";
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
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

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);
	my ($c, $uri, $head);

	while (my $request = $scgi->accept()) {
		eval { $request->read_env(); };
		next if $@;

		$uri = $request->env->{REQUEST_URI};
		$uri =~ s!^/unbuf!!;

		$head = $request->env->{REQUEST_METHOD} eq 'HEAD';

		$c = $request->connection();

		if ($uri eq '/') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS-BUT-NOT-THIS\n");

		} elsif ($uri eq '/zero') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 0\n\n");
			$c->print("NOT-THIS\n");

		} elsif ($uri eq '/short') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");
			$c->print("SEE-THIS-TOO-SHORT-RESPONSE\n");

		} elsif ($uri eq '/empty') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");

		} elsif ($uri eq '/head/empty') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS") unless $head;

		} elsif ($uri eq '/head/matching') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS");

		} elsif ($uri eq '/head/extra') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 8\n\n");
			$c->print("SEE-THIS-BUT-NOT-THIS\n");

		} elsif ($uri eq '/head/short') {
			$c->print("Content-Type: text/html\n");
			$c->print("Content-Length: 100\n\n");
			$c->print("SEE-THIS\n");
		}
	}
}

###############################################################################
