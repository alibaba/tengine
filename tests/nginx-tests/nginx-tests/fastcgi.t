#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /catch {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI "/stderr";
            fastcgi_catch_stderr sample;
        }

        location /var {
            fastcgi_pass $arg_b;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request');
like(http_get('/redir'), qr/ 302 /, 'fastcgi redirect');
like(http_get('/'), qr/^3$/m, 'fastcgi third request');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled');
like(http_get('/catch'), qr/502 Bad/, 'catch stderr');

like(http_get('/var?b=127.0.0.1:' . port(8081)), qr/SEE-THIS/,
	'fastcgi with variables');
like(http_get('/var?b=u'), qr/SEE-THIS/, 'fastcgi with variables to upstream');

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		if ($ENV{REQUEST_URI} eq '/stderr') {
			warn "sample stderr text" x 512;
		}

		print <<EOF;
Location: http://localhost/redirect
Content-Type: text/html

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
