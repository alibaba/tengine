#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend with cache.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi cache shmem/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    fastcgi_cache_path   %%TESTDIR%%/cache  levels=1:2
                         keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
            fastcgi_cache NAME;
            fastcgi_cache_key $request_uri;
            fastcgi_cache_valid 302 1m;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get('/'), qr/SEE-THIS.*^1$/ms, 'fastcgi request');
like(http_get('/'), qr/SEE-THIS.*^1$/ms, 'fastcgi request cached');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in cached HEAD');

SKIP: {
skip 'broken with header crossing buffer boundary', 2
	unless $ENV{TEST_NGINX_UNSAFE};

like(http_get('/stderr'), qr/SEE-THIS.*^2$/ms, 'large stderr handled');
like(http_get('/stderr'), qr/SEE-THIS.*^2$/ms, 'large stderr cached');

}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		if ($ENV{REQUEST_URI} eq '/stderr') {
			warn "sample stderr text" x 512;
		}

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
