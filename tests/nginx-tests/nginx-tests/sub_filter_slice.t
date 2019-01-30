#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for slice filter with sub filter.

# A response is sent using chunked encoding.

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

my $t = Test::Nginx->new()->has(qw/http proxy slice sub/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            sub_filter foo bar;
            sub_filter_types *;

            slice 2;

            proxy_pass    http://127.0.0.1:8081/;

            proxy_set_header   Range  $slice_range;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('t', '0123456789');
$t->run();

###############################################################################

my $r;

# range filter in subrequests (subrequest_ranges)

$r = get('/t', 'Range: bytes=2-4');
unlike($r, qr/\x0d\x0a?0\x0d\x0a?\x0d\x0a?\w/, 'only final chunk');

TODO: {
local $TODO = 'not yet';

# server is assumed to return the requested range

$r = get('/t', 'Range: bytes=3-4');
like($r, qr/ 206 /, 'range request - 206 partial reply');
is(Test::Nginx::http_content($r), '34', 'range request - correct content');

}

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
