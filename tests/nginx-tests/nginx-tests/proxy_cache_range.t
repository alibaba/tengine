#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache and range filter.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

{
local $TODO = 'not yet' unless $t->has_version('1.5.13');

like(http_get_range('/t.html?1', 'Range: bytes=4-'), qr/^THIS/m,
	'range on first request');
}

{
local $TODO = 'not yet';

like(http_get_range('/t.html?2', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'multipart range on first request');
}

like(http_get_range('/t.html?1', 'Range: bytes=4-'), qr/^THIS/m,
	'cached range');
like(http_get_range('/t.html?1', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'cached multipart range');

like(`grep -F '[alert]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no alerts');

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
