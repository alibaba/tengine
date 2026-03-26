#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http keepalive connections on worker shutdown.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=one:1m  rate=1r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_req  zone=one  burst=5;
        }
    }
}

EOF

$t->write_file('test.html', 'XtestX');
$t->run();

###############################################################################

# signaling on graceful shutdown to client that keepalive connection is closing

my $s = http(<<EOF, start => 1);
HEAD /test.html HTTP/1.1
Host: localhost

HEAD /test.html HTTP/1.1
Host: localhost

EOF

select undef, undef, undef, 0.1;

$t->stop();

like(http_end($s), qr/Connection: close/, 'connection close on exit');

###############################################################################
