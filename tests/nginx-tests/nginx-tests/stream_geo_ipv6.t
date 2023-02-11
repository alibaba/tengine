#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Stream tests for geo module with IPv6.

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

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_map stream_geo/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

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

    map $server_port $var {
        %%PORT_8080%%  "::1";
        %%PORT_8081%%  "::ffff:192.0.2.1";
    }

    geo $var $geo_var {
        default    default;
        192.0.2.1  test;
    }

    geo $var $geo_var_ranges {
        ranges;
        default              default;
        127.0.0.1-127.0.0.2  loopback;
        192.0.2.0-192.0.2.1  test;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  [::1]:%%PORT_8080%%;
    }

    server {
        listen  [::1]:%%PORT_8080%%;
        return  "geo:$geo
                 geo_delete:$geo_delete
                 geo_var:$geo_var
                 geo_var_ranges:$geo_var_ranges";
    }

    server {
        listen  127.0.0.1:8081;
        return  "geo_var:$geo_var
                 geo_var_ranges:$geo_var_ranges";
    }
}

EOF

$t->try_run('no inet6 support')->plan(6);

###############################################################################

my %data = stream('127.0.0.1:' . port(8080))->read() =~ /(\w+):(\w+)/g;
is($data{geo}, 'loopback', 'geo ipv6');
is($data{geo_delete}, 'world', 'geo ipv6 delete');
is($data{geo_var}, 'default', 'geo ipv6 from variable');
is($data{geo_var_ranges}, 'default', 'geo ipv6 from variable range');

%data = stream('127.0.0.1:' . port(8081))->read() =~ /(\w+):(\w+)/g;
is($data{geo_var}, 'test', 'geo ipv6 ipv4-mapped from variable');
is($data{geo_var_ranges}, 'test', 'geo ipv6 ipv4-mapped from variable range');

###############################################################################
