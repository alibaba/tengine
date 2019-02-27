#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy_bind transparent with Linux CAP_NET_RAW capability.
# Ensure that such configuration isn't broken under a non-priveleged user.

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

plan(skip_all => 'no linux capability') if $^O ne 'linux';
plan(skip_all => 'must be root') if $> != 0;
plan(skip_all => '127.0.0.2 local address required')
	unless defined IO::Socket::INET->new( LocalAddr => '127.0.0.2' );

my $t = Test::Nginx->new()->has(qw/http proxy/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen          127.0.0.1:8080;
        server_name     localhost;

        location / {
            proxy_bind  127.0.0.2 transparent;
            proxy_pass  http://127.0.0.1:8081/;
        }
    }

    server {
        listen          127.0.0.1:8081;
        server_name     localhost;

        location / {
            add_header   X-IP $remote_addr always;
        }
    }
}

EOF

$t->run()->plan(1);

###############################################################################

like(http_get('/'), qr/X-IP: 127.0.0.2/, 'transparent');

###############################################################################
