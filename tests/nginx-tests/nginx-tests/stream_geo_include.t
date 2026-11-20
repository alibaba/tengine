#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for stream geo module, include directive.

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

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_geo/);

plan(skip_all => 'not yet') until $t->has_version('1.29.8');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    geo $geo_inc_wildcard {
        include       geo*.conf;
    }

    server {
        listen  127.0.0.1:8080;
        return  "geo_inc_wildcard:$geo_inc_wildcard";
    }

}

EOF

$t->write_file('geo_inc_wildcard.conf', '127.0.0.0/8  loopback;');

$t->run()->plan(1);

###############################################################################

my %data = stream('127.0.0.1:' . port(8080))->read() =~ /(\w+):(\w+)/g;
is($data{geo_inc_wildcard}, 'loopback', 'geo');

###############################################################################
