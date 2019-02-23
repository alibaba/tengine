#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for fastcgi backend with unix socket.

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

eval { require IO::Socket::UNIX; };
plan(skip_all => 'IO::Socket::UNIX not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http fastcgi unix/)->plan(6)
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
            fastcgi_pass unix:%%TESTDIR%%/unix.sock;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /var {
            fastcgi_pass $arg_b;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

my $path = $t->testdir() . '/unix.sock';

$t->run_daemon(\&fastcgi_daemon, $path);
$t->run();

# wait for unix socket to appear

for (1 .. 50) {
	last if -S $path;
	select undef, undef, undef, 0.1;
}

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request');
like(http_get('/redir'), qr/ 302 /, 'fastcgi redirect');
like(http_get('/'), qr/^3$/m, 'fastcgi third request');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled');

like(http_get("/var?b=unix:$path"), qr/SEE-THIS/, 'fastcgi with variables');

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket(shift, 5);
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
