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
        listen       127.0.0.1:%%PORT_8182%%-%%PORT_8183%%;
        listen       [::1]:%%PORT_8182%%-%%PORT_8183%%;
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
        listen       127.0.0.1:8181;
        listen       127.0.0.1:8184;
        listen       [::1]:%%PORT_8181%%;
        listen       [::1]:%%PORT_8184%%;
        server_name  localhost;
    }
}

EOF

my $p0 = port(8080); my $p3 = port(8183);
my $p1 = port(8181); my $p4 = port(8184);
my $p2 = port(8182);

plan(skip_all => 'no requested ranges')
	if "$p2$p3" ne "81828183";

$t->run()->plan(9);

###############################################################################

like(http_get("/?b=127.0.0.1:$p0"), qr/127.0.0.1:$p0/, 'single');
unlike(http_get("/?b=127.0.0.1:$p1"), qr/127.0.0.1:$p1/, 'out of range 1');
like(http_get("/?b=127.0.0.1:$p2"), qr/127.0.0.1:$p2/, 'range 1');
like(http_get("/?b=127.0.0.1:$p3"), qr/127.0.0.1:$p3/, 'range 2');
unlike(http_get("/?b=127.0.0.1:$p4"), qr/127.0.0.1:$p4/, 'out of range 2');

unlike(http_get("/?b=[::1]:$p1"), qr/::1:$p1/, 'inet6 out of range 1');
like(http_get("/?b=[::1]:$p2"), qr/::1:$p2/, 'inet6 range 1');
like(http_get("/?b=[::1]:$p3"), qr/::1:$p3/, 'inet6 range 2');
unlike(http_get("/?b=[::1]:$p4"), qr/::1:$p4/, 'inet6 out of range 2');

###############################################################################
