#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream geo module with binary base.

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

plan(skip_all => 'long configuration parsing') unless $ENV{TEST_NGINX_UNSAFE};

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_geo/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    geo $geo_base_create {
        ranges;
        include  base.conf;
    }

    geo $geo_base_include {
        ranges;
        include  base.conf;
    }

    server {
        listen  127.0.0.1:8080;
        return  "geo_base_create:$geo_base_create
                 geo_base_include:$geo_base_include";
    }
}

EOF

$t->write_file('base.conf', join('', map {
	"127." . $_/256/256 % 256 . "." . $_/256 % 256 . "." . $_ % 256 .
	"-127." . $_/256/256 % 256 . "." . $_/256 % 256 . "." .$_ % 256 . " " .
	($_ == 1 ? "loopback" : "range$_") . ";" } (0 .. 100000)));

$t->run()->plan(2);

###############################################################################

my %data = stream('127.0.0.1:' . port(8080))->read() =~ /(\w+):(\w+)/g;
is($data{geo_base_create}, 'loopback', 'geo binary base create');
is($data{geo_base_include}, 'loopback', 'geo binary base include');

###############################################################################
