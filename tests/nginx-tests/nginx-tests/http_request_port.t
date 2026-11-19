#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http $request_port variable.

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

my $t = Test::Nginx->new()->has(qw/http/);

$t->write_file_expand('nginx.conf', <<'EOF');

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
            add_header X-Port $is_request_port$request_port;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->try_run('no request_port')->plan(5);

###############################################################################

unlike(http_get('/'), qr/X-Port/, 'no host');
unlike(http_host_header('localhost'), qr/X-Port/, 'no port');
like(http_absolute_path('localhost:8080'), qr/:8080/, 'absolute uri');
like(http_host_header('localhost:8080'), qr/:8080/, 'host header');

like(http(<<EOF), qr/:8080/, 'precedence');
GET http://localhost:8080 HTTP/1.0
Host: localhost:9000

EOF

###############################################################################

sub http_host_header {
	my ($host) = @_;
	http(<<EOF);
GET / HTTP/1.0
Host: $host

EOF
}

sub http_absolute_path {
	my ($host) = @_;
	http(<<EOF);
GET http://$host HTTP/1.0
Host: localhost

EOF
}

###############################################################################
