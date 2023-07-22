#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for listen port ranges with a wildcard address.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/);

plan(skip_all => 'listen on wildcard address')
	unless $ENV{TEST_NGINX_UNSAFE};

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       %%PORT_8186%%-%%PORT_8187%%;
        server_name  localhost;

        location / {
            proxy_pass  http://$arg_b/t;
        }

        location /t {
            return  200  $server_addr:$server_port;
        }
    }

    # catch out of range

    server {
        listen       127.0.0.1:8185;
        listen       127.0.0.1:8188;
        server_name  localhost;
    }
}

EOF

my $p5 = port(8185); my $p7 = port(8187);
my $p6 = port(8186); my $p8 = port(8188);

plan(skip_all => 'no requested ranges')
	if "$p6$p7" ne "81868187";

$t->run()->plan(4);

###############################################################################

unlike(http_get("/?b=127.0.0.1:$p5"), qr/127.0.0.1:$p5/, 'out of range 1');
like(http_get("/?b=127.0.0.1:$p6"), qr/127.0.0.1:$p6/, 'wildcard range 1');
like(http_get("/?b=127.0.0.1:$p7"), qr/127.0.0.1:$p7/, 'wildcard range 2');
unlike(http_get("/?b=127.0.0.1:$p8"), qr/127.0.0.1:$p8/, 'out of range 2');

###############################################################################
