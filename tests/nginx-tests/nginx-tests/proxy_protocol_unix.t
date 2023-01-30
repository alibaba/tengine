#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for haproxy protocol with unix socket.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http realip stream stream_realip stream_return unix/)
	->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       unix:%%TESTDIR%%/unix.sock proxy_protocol;
        server_name  localhost;

        add_header X-IP $remote_addr;
        add_header X-PP $proxy_protocol_addr;
        real_ip_header proxy_protocol;

        location / { }
        location /pp {
            set_real_ip_from unix:;
            error_page 404 =200 /t;
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen      unix:%%TESTDIR%%/unix1.sock proxy_protocol;
        return      $remote_addr:$proxy_protocol_addr;
    }

    server {
        listen      unix:%%TESTDIR%%/unix2.sock proxy_protocol;
        return      $remote_addr:$proxy_protocol_addr;

        set_real_ip_from unix:;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  unix:%%TESTDIR%%/unix.sock;

        proxy_protocol on;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  unix:%%TESTDIR%%/unix1.sock;

        proxy_protocol on;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  unix:%%TESTDIR%%/unix2.sock;

        proxy_protocol on;
    }
}

EOF

$t->write_file('t', 'SEE-THIS');
$t->run();

###############################################################################

my $r = http_get('/t');
like($r, qr/X-IP: unix/, 'remote_addr');
like($r, qr/X-PP: 127.0.0.1/, 'proxy_protocol_addr');

$r = http_get('/pp');
like($r, qr/X-IP: 127.0.0.1/, 'remote_addr realip');

# listen proxy_protocol in stream

is(get(8081), 'unix::127.0.0.1', 'stream proxy_protocol');
is(get(8082), '127.0.0.1:127.0.0.1', 'stream proxy_protocol realip');

###############################################################################

sub get {
	Test::Nginx::Stream->new(PeerPort => port(shift))->read();
}

###############################################################################
