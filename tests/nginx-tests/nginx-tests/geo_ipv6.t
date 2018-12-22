#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for geo module with IPv6.

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

my $t = Test::Nginx->new()->has(qw/http geo/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $geo {
        ::1/128         loopback;
        2001:0db8::/32  test;
        ::/0            world;
    }

    geo $geo_delete {
        ::1/128         loopback;
        2001:0db8::/32  test;
        ::/0            world;
        delete          ::1/128;
    }

    geo $geo_proxy {
        ranges;
        proxy                ::1;
        default              default;
        192.0.2.1-192.0.2.1  test;
    }

    geo $arg_ip $geo_arg {
        default       default;
        ::1/128       loopback;
        192.0.2.0/24  test;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://[::1]:%%PORT_8080%%/;
        }
    }

    server {
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location / {
            add_header X-Geo  $geo;
            add_header X-Del  $geo_delete;
            add_header X-XFF  $geo_proxy;
            add_header X-Arg  $geo_arg;
        }

        location /addr {
            add_header X-IP   $remote_addr;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('addr', '');
$t->try_run('no inet6 support');

plan(skip_all => 'no ::1 on host')
	if http_get('/addr') !~ /X-IP: ::1/m;

$t->plan(4);

###############################################################################

like(http_get('/'), qr/^X-Geo: loopback/m, 'geo ipv6');
like(http_get('/'), qr/^X-Del: world/m, 'geo ipv6 delete');

like(http_xff('::ffff:192.0.2.1'), qr/^X-XFF: test/m, 'geo ipv6 ipv4-mapped');
like(http_get('/?ip=::ffff:192.0.2.1'), qr/^X-Arg: test/m,
	'geo ipv6 ipv4-mapped from variable');

###############################################################################

sub http_xff {
	my ($xff) = @_;
	return http(<<EOF);
GET / HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################
