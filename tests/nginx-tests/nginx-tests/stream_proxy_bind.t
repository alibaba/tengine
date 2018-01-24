#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Test for stream proxy_bind directive.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';
plan(skip_all => '127.0.0.2 local address required')
	unless defined IO::Socket::INET->new( LocalAddr => '127.0.0.2' );

my $t = Test::Nginx->new()->has(qw/http proxy stream/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    server {
        listen            127.0.0.1:8081;
        proxy_bind        127.0.0.2;
        proxy_pass        127.0.0.1:8082;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen          127.0.0.1:8080;
        server_name     localhost;

        location / {
            proxy_pass  http://127.0.0.1:8081;
        }
    }

    server {
        listen          127.0.0.1:8082;

        location / {
            add_header   X-IP $remote_addr;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

like(http_get('/'), qr/X-IP: 127.0.0.2/, 'bind');

###############################################################################
