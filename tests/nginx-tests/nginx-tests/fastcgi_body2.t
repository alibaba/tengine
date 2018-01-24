#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for fastcgi backend with large request body,
# with fastcgi_next_upstream directive.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass u;
            fastcgi_param REQUEST_URI $request_uri;
            fastcgi_param CONTENT_LENGTH $content_length;
            # fastcgi_next_upstream error timeout;
            fastcgi_read_timeout 1s;
        }

        location /in_memory {
            fastcgi_pass u;
            fastcgi_param REQUEST_URI $request_uri;
            fastcgi_param CONTENT_LENGTH $content_length;
            # fastcgi_next_upstream error timeout;
            fastcgi_read_timeout 1s;
            client_body_buffer_size 128k;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon, 8081);
$t->run_daemon(\&fastcgi_daemon, 8082);
$t->run();

$t->waitforsocket('127.0.0.1:8081');
$t->waitforsocket('127.0.0.1:8082');

###############################################################################

like(http_get_length('/', 'x' x 102400), qr/X-Length: 102400/,
	'body length - in file');

# force quick recovery, so that the next request wouldn't fail

http_get('/');

like(http_get_length('/in_memory', 'x' x 102400), qr/X-Length: 102400/,
	'body length - in memory');

###############################################################################

sub http_get_length {
	my ($url, $body) = @_;
	my $length = length $body;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Content-Length: $length

$body
EOF
}

###############################################################################

sub fastcgi_daemon {
	my ($port) = @_;
	my $socket = FCGI::OpenSocket("127.0.0.1:$port", 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my ($body, $len);

	while( $request->Accept() >= 0 ) {
		read(STDIN, $body, $ENV{'CONTENT_LENGTH'});
		my $len = length $body;

		sleep 3 if $port == 8081;

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html
X-Length: $len

EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
