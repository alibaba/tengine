#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http geo module with unix socket.

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

my $t = Test::Nginx->new()->has(qw/http geo proxy unix/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $geo {
        default                  default;
        255.255.255.255          none;
    }

    geo $remote_addr $geora {
        default                  default;
        255.255.255.255          none;
    }

    geo $geor {
        ranges;
        0.0.0.0-255.255.255.254  test;
        default                  none;
    }

    geo $remote_addr $georra {
        ranges;
        0.0.0.0-255.255.255.254  test;
        default                  none;
    }

    geo $arg_ip $geo_arg {
        default                  default;
        192.0.2.0/24             test;
    }

    server {
        listen       unix:%%TESTDIR%%/unix.sock;
        server_name  localhost;

        location / {
            add_header X-Geo          $geo;
            add_header X-Addr         $geora;
            add_header X-Ranges       $geor;
            add_header X-Ranges-Addr  $georra;
            add_header X-Arg          $geo_arg;
        }
    }

    server {
        listen       127.0.0.1:8080;

        location / {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

my $r = http_get('/');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.8');

like($r, qr/^X-Geo: none/m, 'geo unix');
like($r, qr/^X-Ranges: none/m, 'geo unix ranges');

}

like($r, qr/^X-Addr: none/m, 'geo unix remote addr');
like($r, qr/^X-Ranges-Addr: none/m, 'geo unix ranges remote addr');

like(http_get('/?ip=192.0.2.1'), qr/^X-Arg: test/m, 'geo unix variable');

###############################################################################
