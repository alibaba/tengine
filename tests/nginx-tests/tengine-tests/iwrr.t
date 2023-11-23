#!/usr/bin/perl

# Copyright (C) 2010-2023 Alibaba Group Holding Limited
# Copyright (C) 2010-2023 Zhuozhi Ji (jizhuozhi.george@gmail.com)

# Tests for upstream iwrr balancer module.

###############################################################################

use warnings;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip/ ;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone iwrr/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        iwrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 down;
    }

    upstream w {
        iwrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082 weight=2;
    }

    upstream zone {
        iwrr;
        server 127.0.0.1:8081;
    }

    upstream b {
        iwrr;
        server 127.0.0.1:8081 down;
        server 127.0.0.1:8082 backup;
    }

    upstream d {
        iwrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 weight=2;
        server 127.0.0.1:8084 down;
    }

    upstream g {
        iwrr;
        server 127.0.0.1:8081 weight=2;
        server 127.0.0.1:8082 weight=4;
        server 127.0.0.1:8083 weight=8;
    }

    upstream h {
        iwrr;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
    }

    upstream i {
        iwrr;
        server 127.0.0.1:8081 down;
        server 127.0.0.1:8082 backup;
        server 127.0.0.1:8083 backup;
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

        location /g {
            proxy_pass http://g;
        }

        location /h {
            proxy_pass http://h;
        }

        location /i {
            proxy_pass http://i;
        }
    }
}

EOF

$t->try_run('no upstream iwrr')->plan(18);

###############################################################################
my $r;
my %list = ();

$list{'8083'} = 0;
$list{http_get_body('/')} = 1;
$list{http_get_body('/')} = 1;
$list{http_get_body('/')} = 1;

is($list{'8081'}, 1, 'iwrr 8081');
is($list{'8082'}, 1, 'iwrr 8082');
is($list{'8083'}, 0, 'peer down');

%list = ();
$list{http_get_body('/w')} += 1;
$list{http_get_body('/w')} += 1;
$list{http_get_body('/w')} += 1;

is($list{'8081'}, 1, 'weight 1');
is($list{'8082'}, 2, 'weight 2');

%list = ();
$list{http_get_body('/zone')} += 1;

is($list{'8081'}, 1, 'iwrr zone');

%list = ();
$list{http_get_body('/b')} += 1;

is($list{'8082'}, 1, 'iwrr backup');

%list = ();
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;
$list{http_get_body('/d')} += 1;

is($list{'8081'}, 1, 'weight 1');
is($list{'8082'}, 1, 'weight 1');
is($list{'8083'}, 2, 'weight 2');

%list = ();
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;
$list{http_get_body('/g')} += 1;

is($list{'8081'}, 2, 'weight 2');
is($list{'8082'}, 4, 'weight 4');
is($list{'8083'}, 8, 'weight 8');

%list = ();
$list{http_get_body('/h')} += 1;
$list{http_get_body('/h')} += 1;
$list{http_get_body('/h')} += 1;

is($list{'8081'}, 1, 'weight 1');
is($list{'8082'}, 1, 'weight 1');
is($list{'8083'}, 1, 'weight 1');

%list = ();
$list{http_get_body('/i')} += 1;
$list{http_get_body('/i')} += 1;

is($list{'8082'}, 1, 'weight 1');
is($list{'8083'}, 1, 'weight 1');


###############################################################################

sub http_get_body {
        my ($uri) = @_;

        return undef if !defined $uri;

        http_get($uri) =~ /(.*?)\x0d\x0a?\x0d\x0a?(.*)/ms;

        return $2;
}

###############################################################################