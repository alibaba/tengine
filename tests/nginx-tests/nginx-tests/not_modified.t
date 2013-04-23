#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for not modified filter module.

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

my $t = Test::Nginx->new()->has('http')->plan(12)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            if_modified_since before;
        }
    }
}

EOF

$t->write_file('t', '');

$t->run();

###############################################################################

like(http_get_ims('/t', 'Wed, 08 Jul 2037 22:53:52 GMT'), qr/304/,
	'0x7F000000');
like(http_get_ims('/t', 'Tue, 19 Jan 2038 03:14:07 GMT'), qr/304/,
	'0x7FFFFFFF');

SKIP: {
	skip "only for 32-bit time_t", 2 if (gmtime(0xFFFFFFFF))[5] == 206;

	like(http_get_ims('/t', 'Tue, 19 Jan 2038 03:14:08 GMT'), qr/200/,
		'0x7FFFFFFF + 1');
	like(http_get_ims('/t', 'Fri, 25 Feb 2174 09:42:23 GMT'), qr/200/,
		'0x17FFFFFFF');
}

# If-Match, If-None-Match tests

my ($t1, $etag);

$t1 = http_get('/t');

SKIP: {
    skip "no etag support", 8 if $t1 !~ /ETag: (".*")/;
    $etag = $1;

    like(http_get_inm('/t', $etag), qr/304/, 'if-none-match');
    like(http_get_inm('/t', '"foo"'), qr/200/, 'if-none-match fail');
    like(http_get_inm('/t', '"foo", "bar", ' . $etag . ' , "baz"'), qr/304/,
	'if-none-match with complex list');
    like(http_get_inm('/t', '*'), qr/304/, 'if-none-match all');

    like(http_get_im('/t', $etag), qr/200/, 'if-match');
    like(http_get_im('/t', '"foo"'), qr/412/, 'if-match fail');
    like(http_get_im('/t', '"foo", "bar", ' . "\t" . $etag . ' , "baz"'),
	qr/200/, 'if-match with complex list');
    like(http_get_im('/t', '*'), qr/200/, 'if-match all');
}

###############################################################################

sub http_get_ims {
	my ($url, $ims) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
If-Modified-Since: $ims

EOF
}

sub http_get_inm {
	my ($url, $inm) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
If-None-Match: $inm

EOF
}

sub http_get_im {
	my ($url, $inm) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
If-Match: $inm

EOF
}

###############################################################################
