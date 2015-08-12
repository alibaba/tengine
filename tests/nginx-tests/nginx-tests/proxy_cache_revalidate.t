#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache revalidation with conditional requests.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=one:1m;

    proxy_cache_revalidate on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   one;

            proxy_cache_valid  200  1s;

            add_header X-Cache-Status $upstream_cache_status;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
    }
}

EOF

$t->write_file('t', 'SEE-THIS');
$t->write_file('t2', 'SEE-THIS');

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no proxy_cache_revalidate') if $@;
$t->plan(9);

###############################################################################

# request documents and make sure they are cached

like(http_get('/t'), qr/X-Cache-Status: MISS.*SEE/ms, 'request');
like(http_get('/t'), qr/X-Cache-Status: HIT.*SEE/ms, 'request cached');

like(http_get('/t2'), qr/X-Cache-Status: MISS.*SEE/ms, '2nd request');
like(http_get('/t2'), qr/X-Cache-Status: HIT.*SEE/ms, '2nd request cached');

# wait for a while for cached responses to expire

select undef, undef, undef, 2.5;

# 1st document isn't modified, and should be revalidated on first request
# (a 304 status code will appear in backend's logs), then cached again

like(http_get('/t'), qr/X-Cache-Status: REVALIDATED.*SEE/ms, 'revalidated');
like(http_get('/t'), qr/X-Cache-Status: HIT.*SEE/ms, 'request cached');

select undef, undef, undef, 0.1;
like(read_file($t->testdir() . '/access.log'), qr/ 304 /, 'not modified');

# 2nd document is recreated with a new content

$t->write_file('t2', 'NEW');
like(http_get('/t2'), qr/X-Cache-Status: EXPIRED.*NEW/ms, 'revalidate failed');
like(http_get('/t2'), qr/X-Cache-Status: HIT.*NEW/ms, 'new response cached');

###############################################################################

sub read_file {
	my ($file) = @_;
	my $log;

        local $/;

        open LOG, $file or die "Can't open $file: $!\n";
        $log = <LOG>;
        close LOG;

	return $log;
}

###############################################################################
