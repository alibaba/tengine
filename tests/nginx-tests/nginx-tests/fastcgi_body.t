#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend with chunked request body.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(5)
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
            fastcgi_param CONTENT_LENGTH $content_length;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get('/'), qr/X-Body: /, 'fastcgi no body');

like(http_get_length('/', ''), qr/X-Body: /, 'fastcgi empty body');
like(http_get_length('/', 'foobar'), qr/X-Body: foobar/, 'fastcgi body');

like(http(<<EOF), qr/X-Body: foobar/, 'fastcgi chunked');
GET / HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

6
foobar
0

EOF

like(http(<<EOF), qr/X-Body: /, 'fastcgi empty chunked');
GET / HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

0

EOF

###############################################################################

sub http_get_length {
	my ($url, $body) = @_;
	my $length = length $body;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Content-Length: $length

$body
EOF
}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	my $body;

	while( $request->Accept() >= 0 ) {
		$count++;
		read(STDIN, $body, $ENV{'CONTENT_LENGTH'});

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html
X-Body: $body

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
