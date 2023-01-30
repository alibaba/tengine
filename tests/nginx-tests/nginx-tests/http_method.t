#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP methods.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF')->run();

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
            return 200;
        }
    }
}

EOF

###############################################################################

like(http(<<EOF), qr/405 Not Allowed(?!.*200 OK)/s, 'trace');
TRACE / HTTP/1.1
Host: localhost

GET / HTTP/1.1
Host: localhost
Connection: close

EOF

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

like(http(<<EOF), qr/405 Not Allowed(?!.*200 OK)/s, 'connect');
CONNECT / HTTP/1.1
Host: localhost

GET / HTTP/1.1
Host: localhost
Connection: close

EOF

}

###############################################################################
