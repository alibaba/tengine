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

my $t = Test::Nginx->new()->has('http')->plan(4)
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

###############################################################################

sub http_get_ims {
        my ($url, $ims) = @_;
        return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
If-Modified-Since: $ims

EOF
}

###############################################################################
