#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for nginx geo module with binary base.

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

plan(skip_all => 'long configuration parsing') unless $ENV{TEST_NGINX_UNSAFE};

my $t = Test::Nginx->new()->has(qw/http geo/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $geo_base_create {
        ranges;
        include  base.conf;
    }

    geo $geo_base_include {
        ranges;
        include  base.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-IP   $remote_addr;
            add_header X-GBc  $geo_base_create;
            add_header X-GBi  $geo_base_include;
        }
    }
}

EOF

$t->write_file('1', '');
$t->write_file('base.conf', join('', map {
	"127." . $_/256/256 % 256 . "." . $_/256 % 256 . "." . $_ % 256 .
	"-127." . $_/256/256 % 256 . "." . $_/256 % 256 . "." .$_ % 256 . " " .
	($_ == 1 ? "loopback" : "range$_") . ";" } (0 .. 100000)));

$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/1') !~ /X-IP: 127.0.0.1/m;

$t->plan(2);

###############################################################################

my $r = http_get('/1');
like($r, qr/^X-GBc: loopback/m, 'geo binary base create');
like($r, qr/^X-GBi: loopback/m, 'geo binary base include');

###############################################################################
