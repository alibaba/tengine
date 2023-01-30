#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for listen port ranges.

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

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:%%PORT_8082%%-%%PORT_8083%%;
        listen       %%PORT_8085%%-%%PORT_8086%%;
        listen       [::1]:%%PORT_8085%%-%%PORT_8086%%;
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
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8084;
        listen       127.0.0.1:8087;
        listen       [::1]:%%PORT_8084%%;
        listen       [::1]:%%PORT_8087%%;
        server_name  localhost;
    }
}

EOF

my $p0 = port(8080); my $p3 = port(8083); my $p6 = port(8086);
my $p1 = port(8081); my $p4 = port(8084); my $p7 = port(8087);
my $p2 = port(8082); my $p5 = port(8085);

plan(skip_all => 'listen on wildcard address')
	unless $ENV{TEST_NGINX_UNSAFE};

plan(skip_all => 'no requested ranges')
	if "$p0$p1$p2$p3$p4$p5$p6$p7" ne "80808081808280838084808580868087";

$t->run()->plan(12);

###############################################################################

like(http_get("/?b=127.0.0.1:$p0"), qr/127.0.0.1:$p0/, 'single');
unlike(http_get("/?b=127.0.0.1:$p1"), qr/127.0.0.1:$p1/, 'out of range 1');
like(http_get("/?b=127.0.0.1:$p2"), qr/127.0.0.1:$p2/, 'range 1');
like(http_get("/?b=127.0.0.1:$p3"), qr/127.0.0.1:$p3/, 'range 2');
unlike(http_get("/?b=127.0.0.1:$p4"), qr/127.0.0.$p4/, 'out of range 2');
like(http_get("/?b=127.0.0.1:$p5"), qr/127.0.0.1:$p5/, 'wildcard range 1');
like(http_get("/?b=127.0.0.1:$p6"), qr/127.0.0.1:$p6/, 'wildcard range 2');
unlike(http_get("/?b=127.0.0.1:$p7"), qr/127.0.0.1:$p7/, 'out of range 3');

unlike(http_get("/?b=[::1]:$p4"), qr/::1:$p4/, 'out of range 4');
like(http_get("/?b=[::1]:$p5"), qr/::1:$p5/, 'ipv6 range 1');
like(http_get("/?b=[::1]:$p6"), qr/::1:$p6/, 'ipv6 range 2');
unlike(http_get("/?b=[::1]:$p7"), qr/::1:$p7/, 'out of range 5');

###############################################################################
