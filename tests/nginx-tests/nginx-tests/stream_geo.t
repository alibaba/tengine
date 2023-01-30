#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream geo module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_map stream_geo/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

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

    geo $remote_addr $geo_from_addr {
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
    }

    map $server_port $var {
        %%PORT_8080%%  "192.0.2.1";
        %%PORT_8081%%  "10.0.0.1";
        %%PORT_8085%%  "10.11.2.1";
        %%PORT_8086%%  "loopback";
        %%PORT_8087%%  "10.13.2.1";
    }

    geo $var $geo_from_var {
        default       default;
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
    }

    geo $var $geo_var_ranges {
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

    geo $var $geo_world {
        127.0.0.0/8   loopback;
        192.0.2.0/24  test;
        0.0.0.0/0     world;
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
        listen  127.0.0.1:8080;
        return  "geo:$geo
                 geo_include:$geo_include
                 geo_delete:$geo_delete
                 geo_ranges:$geo_ranges
                 geo_ranges_include:$geo_ranges_include
                 geo_before:$geo_before
                 geo_after:$geo_after
                 geo_insert:$geo_insert
                 geo_insert_before:$geo_insert_before
                 geo_insert_after:$geo_insert_after
                 geo_from_addr:$geo_from_addr
                 geo_from_var:$geo_from_var";
    }

    server {
        listen  127.0.0.1:8081;
        return  $geo_from_var;
    }

    server {
        listen  127.0.0.1:8082;
        return  $geo_world;
    }

    server {
        listen  127.0.0.1:8083;
        return  $geo_ranges_delete;
    }

    server {
        listen  127.0.0.1:8084;
        return  $geo_ranges_delete_2;
    }

    server {
        listen  127.0.0.1:8085;
        return  $geo_var_ranges;
    }

    server {
        listen  127.0.0.1:8086;
        return  $geo_var_ranges;
    }

    server {
        listen  127.0.0.1:8087;
        return  $geo_var_ranges;
    }
}

EOF

$t->write_file('geo.conf', '127.0.0.0/8  loopback;');
$t->write_file('geo-ranges.conf', '127.0.0.0-127.255.255.255  loopback;');

$t->run()->plan(19);

###############################################################################

my %data = stream('127.0.0.1:' . port(8080))->read() =~ /(\w+):(\w+)/g;
is($data{geo}, 'loopback', 'geo');
is($data{geo_include}, 'loopback', 'geo include');
is($data{geo_delete}, 'world', 'geo delete');
is($data{geo_ranges}, 'loopback', 'geo ranges');
is($data{geo_ranges_include}, 'loopback', 'geo ranges include');

is(stream('127.0.0.1:' . port(8083))->read(), 'default', 'geo ranges delete');
is(stream('127.0.0.1:' . port(8084))->read(), 'default', 'geo ranges delete 2');

is($data{geo_before}, 'loopback', 'geo ranges add before');
is($data{geo_after}, 'loopback', 'geo ranges add after');
is($data{geo_insert}, 'loopback', 'geo ranges insert');
is($data{geo_insert_before}, 'loopback', 'geo ranges insert before');
is($data{geo_insert_after}, 'loopback', 'geo ranges insert after');

is($data{geo_from_addr}, 'loopback', 'geo from addr');
is($data{geo_from_var}, 'test', 'geo from var');

is(stream('127.0.0.1:' . port(8085))->read(), 'default',
	'geo delete range from variable');

is(stream('127.0.0.1:' . port(8081))->read(), 'default', 'geo default');
is(stream('127.0.0.1:' . port(8082))->read(), 'world', 'geo world');
is(stream('127.0.0.1:' . port(8086))->read(), 'default', 'geo ranges default');
is(stream('127.0.0.1:' . port(8087))->read(), 'foo2', 'geo ranges add');

###############################################################################
