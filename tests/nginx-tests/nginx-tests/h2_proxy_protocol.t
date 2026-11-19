#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with proxy_protocol.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 realip/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 proxy_protocol;
        server_name  localhost;

        http2 on;

        location /pp {
            set_real_ip_from 127.0.0.1/32;
            real_ip_header proxy_protocol;
            alias %%TESTDIR%%/t.html;
            add_header X-PP $remote_addr;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

my $proxy = 'PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
my $s = Test::Nginx::HTTP2->new(port(8080), proxy => $proxy);
my $sid = $s->new_stream({ path => '/pp' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'PROXY HEADERS frame');
is($frame->{headers}->{'x-pp'}, '192.0.2.1', 'PROXY remote addr');

# invalid PROXY protocol string

$proxy = 'BOGUS TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
ok(!http($proxy), 'PROXY invalid protocol');

###############################################################################
