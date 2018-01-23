#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend with fastcgi_buffering off.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi ssi/)
	->write_file_expand('nginx.conf', <<'EOF');

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
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
            fastcgi_buffering off;
        }

        location /inmemory.html {
            ssi on;
        }
    }
}

EOF

$t->write_file('inmemory.html',
	'<!--#include virtual="/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->run()->plan(2);

$t->run_daemon(\&fastcgi_daemon)->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi unbuffered');
like(http_get('/inmemory.html'), qr/set: SEE-THIS/, 'fastcgi inmemory');

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		# this intentionally uses multiple print()'s to test
		# parsing of multiple records

		print(
			"Status: 200 OK" . CRLF .
			"Content-Type: text/plain" . CRLF . CRLF
		);

		print "SEE";
		print "-THIS" . CRLF;
		print "$count" . CRLF;
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
