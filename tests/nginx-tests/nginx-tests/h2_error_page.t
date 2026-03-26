#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with error_page directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 rewrite/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;
        lingering_close off;

        error_page 400 = /close;

        location / { }

        location /close {
            return 444;
        }
    }
}

EOF

$t->run();

###############################################################################

# tests for socket leaks with "return 444" in error_page

my ($sid, $frames, $frame);

# make sure there is no socket leak when the request is rejected
# due to missing mandatory ":scheme" pseudo-header and "return 444;"
# is used in error_page 400 (ticket #274)

my $s1 = Test::Nginx::HTTP2->new();
$sid = $s1->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':path', value => '/' },
	{ name => ':authority', value => 'localhost' }]});
$frames = $s1->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'error 400 return 444 - missing header');

# make sure there is no socket leak when the request is rejected
# due to invalid method with lower-case letters and "return 444;"
# is used in error_page 400 (ticket #2455)

my $s2 = Test::Nginx::HTTP2->new();
$sid = $s2->new_stream({ method => 'foo' });
$frames = $s2->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'error 400 return 444 - invalid header');

# while keeping $s1 and $s2, stop nginx; this should result in
# "open socket ... left in connection ..." alerts if any of these
# sockets are still open

$t->stop();

###############################################################################
