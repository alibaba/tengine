#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Test for fastcgi backend, responses with extra data or premature close.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()
	->has(qw/http fastcgi cache rewrite addition/)->plan(22)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    fastcgi_param REQUEST_URI $request_uri;
    fastcgi_param REQUEST_METHOD $request_method;

    fastcgi_cache_path cache keys_zone=one:1m;
    fastcgi_cache_key $request_uri;
    fastcgi_cache_valid any 1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass 127.0.0.1:8081;
            add_after_body /after;
        }

        location /unbuf/ {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_buffering off;
            add_after_body /after;
        }

        location /head/ {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_cache one;
            add_after_body /after;
        }

        location /after {
            return 200 ":after\n";
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
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

like(http_get('/head/empty'), qr/200 OK/, 'head no body cached');
like(http_get('/head/matching'), qr/SEE-THIS/, 'head matching cached');
like(http_get('/head/extra'), qr/SEE-THIS(?!-BUT-NOT-THIS)/s,
	'head extra cached');
like(http_get('/head/short'), qr/SEE-THIS(?!.*:after)/s,
	'head too short cached');

# "zero size buf" alerts (ticket #2018)

like(http_get('/zero'), qr/200 OK(?!.*NOT-THIS)/s, 'zero size');
like(http_get('/unbuf/zero'), qr/200 OK(?!.*NOT-THIS)/s,
	'unbuffered zero size');

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my ($uri, $head);

	while( $request->Accept() >= 0 ) {
		$uri = $ENV{REQUEST_URI};
		$uri =~ s!^/unbuf!!;

		$head = $ENV{REQUEST_METHOD} eq 'HEAD';

		if ($uri eq '/') {
			print "Content-Type: text/html\n";
			print "Content-Length: 8\n\n";
			print "SEE-THIS-BUT-NOT-THIS\n";

		} elsif ($uri eq '/zero') {
			print "Content-Type: text/html\n";
			print "Content-Length: 0\n\n";
			print "NOT-THIS\n";

		} elsif ($uri eq '/short') {
			print "Content-Type: text/html\n";
			print "Content-Length: 100\n\n";
			print "SEE-THIS-TOO-SHORT-RESPONSE\n";

		} elsif ($uri eq '/empty') {
			print "Content-Type: text/html\n";
			print "Content-Length: 100\n\n";

		} elsif ($uri eq '/head/empty') {
			print "Content-Type: text/html\n";
			print "Content-Length: 8\n\n";
			print "SEE-THIS" unless $head;

		} elsif ($uri eq '/head/matching') {
			print "Content-Type: text/html\n";
			print "Content-Length: 8\n\n";
			print "SEE-THIS";

		} elsif ($uri eq '/head/extra') {
			print "Content-Type: text/html\n";
			print "Content-Length: 8\n\n";
			print "SEE-THIS-BUT-NOT-THIS\n";

		} elsif ($uri eq '/head/short') {
			print "Content-Type: text/html\n";
			print "Content-Length: 100\n\n";
			print "SEE-THIS\n";
		}
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
