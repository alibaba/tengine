#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for haproxy protocol on IPv6 listening socket.

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

my $t = Test::Nginx->new()->has(qw/http realip stream/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       [::1]:%%PORT_8080%% proxy_protocol;
        server_name  localhost;

        add_header X-IP $remote_addr;
        add_header X-PP $proxy_protocol_addr;
        real_ip_header proxy_protocol;

        location / { }
        location /pp {
            set_real_ip_from ::1/128;
            error_page 404 =200 /t;
        }
    }
}

stream {
    server {
        listen      127.0.0.1:8080;
        proxy_pass  [::1]:%%PORT_8080%%;

        proxy_protocol on;
    }
}

EOF

$t->write_file('t', 'SEE-THIS');
$t->try_run('no inet6 support')->plan(3);

###############################################################################

my $r = http_get('/t');
like($r, qr/X-IP: ::1/, 'realip');
like($r, qr/X-PP: 127.0.0.1/, 'proxy protocol');

$r = http_get('/pp');
like($r, qr/X-IP: 127.0.0.1/, 'proxy protocol realip');

###############################################################################
