#!/usr/bin/perl

# Copyright (C) 2010-2019 Alibaba Group Holding Limited

# Tests for upstream vnswrr balancer module.

###############################################################################

use warnings;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip/ ;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone vnswrr/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        vnswrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 down;
    }

    upstream w {
        vnswrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082 weight=2;
    }

    upstream zone {
        vnswrr;
        server 127.0.0.1:8081;
    }

    upstream b {
        vnswrr;
        server 127.0.0.1:8081 down;
        server 127.0.0.1:8082 backup;
    }

    upstream d {
        vnswrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 weight=2;
        server 127.0.0.1:8084 down;
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        listen       127.0.0.1:8083;
        server_name  localhost;

        location / {
            return 200 $server_port;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }

        location /w {
            proxy_pass http://w;
        }

        location /zone {
            proxy_pass http://zone;
        }

        location /b {
            proxy_pass http://b;
        }

        location /d {
            proxy_pass http://d;
        }
    }
}

EOF

$t->try_run('no upstream vnswrr')->plan(10);

###############################################################################
my $r;
my %list = ();

$list{'8083'} = 0;
$list{http_get_body('/')} = 1;
$list{http_get_body('/')} = 1;
$list{http_get_body('/')} = 1;

is($list{'8081'}, 1, 'vnswrr 8081');
is($list{'8082'}, 1, 'vnswrr 8082');
is($list{'8083'}, 0, 'peer down');

%list = ();
$list{http_get_body('/w')} += 1;
$list{http_get_body('/w')} += 1;
$list{http_get_body('/w')} += 1;

is($list{'8081'}, 1, 'weight 1');
is($list{'8082'}, 2, 'weight 2');

%list = ();
$list{http_get_body('/zone')} += 1;

is($list{'8081'}, 1, 'vnswrr zone');

%list = ();
$list{http_get_body('/b')} += 1;

is($list{'8082'}, 1, 'vnswrr backup');

%list = ();
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;

is($list{'8081'}, 1, 'weight 1');
is($list{'8082'}, 1, 'weight 1');
is($list{'8083'}, 2, 'weight 2');
###############################################################################

sub http_get_body {
        my ($uri) = @_;

        return undef if !defined $uri;

        http_get($uri) =~ /(.*?)\x0d\x0a?\x0d\x0a?(.*)/ms;

        return $2;
}

###############################################################################
