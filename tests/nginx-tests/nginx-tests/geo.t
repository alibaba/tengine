#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for nginx geo module.

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

my $t = Test::Nginx->new()->has(qw/http geo/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $geo {
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
        0.0.0.0/0     world;
    }

    geo $geo_include {
        include       geo.conf;
        192.0.2.0/24  test;
        0.0.0.0/0     world;
    }

    geo $geo_delete {
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
        0.0.0.0/0     world;
        delete        127.0.0.0/8;
    }

    geo $arg_ip $geo_from_arg {
        default       default;
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
    }

    geo $arg_ip $geo_arg_ranges {
        ranges;
        default                default;
        127.0.0.0-127.0.0.1    loopback;

        # ranges with two /16 networks
        # the latter network has greater two least octets
        # (see 1301a58b5dac for details)
        10.10.3.0-10.11.2.255  foo;
        10.12.3.0-10.13.2.255  foo2;
        delete                 10.10.3.0-10.11.2.255;
    }

    geo $geo_proxy {
        default       default;
        proxy         127.0.0.1;
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
    }

    geo $geo_proxy_recursive {
        proxy_recursive;
        default       default;
        proxy         127.0.0.1;
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
    }

    geo $geo_ranges {
        ranges;
        default                    default;
        127.0.0.0-127.255.255.255  loopback;
        192.0.2.0-192.0.2.255      test;
    }

    geo $geo_ranges_include {
        ranges;
        default                default;
        include                geo-ranges.conf;
        192.0.2.0-192.0.2.255  test;
    }

    geo $geo_ranges_delete {
        ranges;
        default                default;
        127.0.0.0-127.0.0.255  test;
        127.0.0.1-127.0.0.1    loopback;
        delete                 127.0.0.0-127.0.0.0;
        delete                 127.0.0.2-127.0.0.255;
        delete                 127.0.0.1-127.0.0.1;
    }

    # delete range with two /16
    geo $geo_ranges_delete_2 {
        ranges;
        default              default;
        127.0.0.0-127.1.0.0  loopback;
        delete               127.0.0.0-127.1.0.0;
    }

    geo $geo_before {
        ranges;
        default                default;
        127.0.0.1-127.0.0.255  loopback;
        127.0.0.0-127.0.0.0    test;
    }

    geo $geo_after {
        ranges;
        default                default;
        127.0.0.0-127.0.0.1    loopback;
        127.0.0.2-127.0.0.255  test;
    }

    geo $geo_insert {
        ranges;
        default                default;
        127.0.0.0-127.0.0.255  test;
        127.0.0.1-127.0.0.2    test2;
        127.0.0.1-127.0.0.1    loopback;
    }

    geo $geo_insert_before {
        ranges;
        default                default;
        127.0.0.0-127.0.0.255  test;
        127.0.0.0-127.0.0.1    loopback;
    }

    geo $geo_insert_after {
        ranges;
        default                default;
        127.0.0.0-127.0.0.255  test;
        127.0.0.1-127.0.0.255  loopback;
     }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-IP   $remote_addr;
            add_header X-Geo  $geo;
            add_header X-Inc  $geo_include;
            add_header X-Del  $geo_delete;
            add_header X-Ran  $geo_ranges;
            add_header X-RIn  $geo_ranges_include;
            add_header X-ABe  $geo_before;
            add_header X-AAf  $geo_after;
            add_header X-Ins  $geo_insert;
            add_header X-IBe  $geo_insert_before;
            add_header X-IAf  $geo_insert_after;
            add_header X-Arg  $geo_from_arg;
            add_header X-ARa  $geo_arg_ranges;
            add_header X-XFF  $geo_proxy;
            add_header X-XFR  $geo_proxy_recursive;
        }

        location /2 {
            add_header X-RDe  $geo_ranges_delete;
            add_header X-RD2  $geo_ranges_delete_2;
        }
    }
}

EOF

$t->write_file('1', '');
$t->write_file('2', '');
$t->write_file('geo.conf', '127.0.0.0/8  loopback;');
$t->write_file('geo-ranges.conf', '127.0.0.0-127.255.255.255  loopback;');

$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/1') !~ /X-IP: 127.0.0.1/m;

$t->plan(22);

###############################################################################

my $r = http_get('/1');
like($r, qr/^X-Geo: loopback/m, 'geo');
like($r, qr/^X-Inc: loopback/m, 'geo include');
like($r, qr/^X-Del: world/m, 'geo delete');
like($r, qr/^X-Ran: loopback/m, 'geo ranges');
like($r, qr/^X-RIn: loopback/m, 'geo ranges include');

like(http_get('/2'), qr/^X-RDe: default/m, 'geo ranges delete');
like(http_get('/2'), qr/^X-RD2: default/m, 'geo ranges delete 2');

like($r, qr/^X-ABe: loopback/m, 'geo ranges add before');
like($r, qr/^X-AAf: loopback/m, 'geo ranges add after');
like($r, qr/^X-Ins: loopback/m, 'geo ranges insert');
like($r, qr/^X-IBe: loopback/m, 'geo ranges insert before');
like($r, qr/^X-IAf: loopback/m, 'geo ranges insert after');

like(http_get('/1?ip=192.0.2.1'), qr/^X-Arg: test/m, 'geo from variable');
like(http_get('/1?ip=10.0.0.1'), qr/^X-Arg: default/m, 'geo default');
like(http_get('/1?ip=10.0.0.1'), qr/^X-ARa: default/m, 'geo ranges default');
like(http_get('/1?ip=10.13.2.1'), qr/^X-ARa: foo2/m, 'geo ranges add');
like(http_get('/1?ip=10.11.2.1'), qr/^X-ARa: default/m,
	'geo delete range from variable');

like(http_xff('192.0.2.1'), qr/^X-XFF: test/m, 'geo proxy');
like(http_xff('10.0.0.1'), qr/^X-XFF: default/m, 'geo proxy default');
like(http_xff('10.0.0.1, 192.0.2.1'), qr/^X-XFF: test/m, 'geo proxy long');

like(http_xff('192.0.2.1, 127.0.0.1'), qr/^X-XFF: loopback/m,
	'geo proxy_recursive off');
like(http_xff('192.0.2.1, 127.0.0.1'), qr/^X-XFR: test/m,
	'geo proxy_recursive on');

###############################################################################

sub http_xff {
	my ($xff) = @_;
	return http(<<EOF);
GET /1 HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################
