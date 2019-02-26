#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for slice filter.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache fastcgi slice rewrite/)
	->plan(76);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  keys_zone=NAME:1m;
    proxy_cache_path   %%TESTDIR%%/cach3  keys_zone=NAME3:1m;
    proxy_cache_key    $uri$is_args$args$slice_range;

    fastcgi_cache_path   %%TESTDIR%%/cache2  keys_zone=NAME2:1m;
    fastcgi_cache_key    $uri$is_args$args$slice_range;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / { }

        location /proxy/ {
            slice 2;

            proxy_pass    http://127.0.0.1:8081/;

            proxy_set_header   Range  $slice_range;
        }

        location /cache/ {
            slice 2;

            proxy_pass    http://127.0.0.1:8081/;

            proxy_cache   NAME;

            proxy_set_header   Range  $slice_range;

            proxy_cache_valid   200 206  1h;

            add_header X-Cache-Status $upstream_cache_status;
        }

        location /fastcgi {
            slice 2;

            fastcgi_pass    127.0.0.1:8082;

            fastcgi_cache   NAME2;

            fastcgi_param   Range $slice_range;

            fastcgi_cache_valid   200 206  1h;

            fastcgi_force_ranges  on;

            add_header X-Cache-Status $upstream_cache_status;
        }

        location /cache-redirect {
            error_page 404 = @fallback;
        }

        location @fallback {
            slice 2;

            proxy_pass    http://127.0.0.1:8081/t$is_args$args;

            proxy_cache   NAME3;

            proxy_set_header   Range  $slice_range;

            proxy_cache_valid   200 206  1h;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            if ($http_range = "") {
                set $limit_rate 100;
	    }
        }
    }
}

EOF

$t->write_file('t', '0123456789abcdef');
$t->run();

###############################################################################

my $r;

like(http_get('/cache/nx'), qr/ 404 /, 'not found');
like(http_get('/cache/t'), qr/ 200 .*0123456789abcdef$/ms, 'no range');

$r = get('/cache/t?single', "Range: bytes=0-0");
like($r, qr/ 206 /, 'single - 206 partial reply');
like($r, qr/^0$/m, 'single - correct content');
like($r, qr/Status: MISS/m, 'single - cache status');

$r = get('/cache/t?single', "Range: bytes=0-0");
like($r, qr/ 206 /, 'single cached - 206 partial reply');
like($r, qr/^0$/m, 'single cached - correct content');
like($r, qr/Status: HIT/m, 'single cached - cache status');

$r = get('/cache/t?single', "Range: bytes=1-1");
like($r, qr/ 206 /, 'single next - 206 partial reply');
like($r, qr/^1$/m, 'single next - correct content');
like($r, qr/Status: HIT/m, 'single next - cache status');

$r = get('/cache/t?single', "Range: bytes=2-2");
like($r, qr/ 206 /, 'slice next - 206 partial reply');
like($r, qr/^2$/m, 'slice next - correct content');
like($r, qr/Status: MISS/m, 'slice next - cache status');

$r = get('/cache/t?single', "Range: bytes=2-2");
like($r, qr/ 206 /, 'slice next cached - 206 partial reply');
like($r, qr/^2$/m, 'slice next cached - correct content');
like($r, qr/Status: HIT/m, 'slice next cached - cache status');

$r = get('/cache/t?median', "Range: bytes=2-2");
like($r, qr/ 206 /, 'slice median - 206 partial reply');
like($r, qr/^2$/m, 'slice median - correct content');
like($r, qr/Status: MISS/m, 'slice median - cache status');

$r = get('/cache/t?median', "Range: bytes=0-0");
like($r, qr/ 206 /, 'before median - 206 partial reply');
like($r, qr/^0$/m, 'before median - correct content');
like($r, qr/Status: MISS/m, 'before median - cache status');

# range span to multiple slices

$r = get('/cache/t?range', "Range: bytes=1-2");
like($r, qr/ 206 /, 'slice range - 206 partial reply');
like($r, qr/^12$/m, 'slice range - correct content');
like($r, qr/Status: MISS/m, 'slice range - cache status');

$r = get('/cache/t?range', "Range: bytes=0-0");
like($r, qr/ 206 /, 'slice 1st - 206 partial reply');
like($r, qr/^0$/m, 'slice 1st - correct content');
like($r, qr/Status: HIT/m, 'slice 1st - cache status');

$r = get('/cache/t?range', "Range: bytes=2-2");
like($r, qr/ 206 /, 'slice 2nd - 206 partial reply');
like($r, qr/^2$/m, 'slice 2nd - correct content');
like($r, qr/Status: HIT/m, 'slice 2nd - cache status');

$r = get('/cache/t?mrange', "Range: bytes=3-4");
like($r, qr/ 206 /, 'range median - 206 partial reply');
like($r, qr/^34$/m, 'range median - correct content');
like($r, qr/Status: MISS/m, 'range median - cache status');

$r = get('/cache/t?mrange', "Range: bytes=2-3");
like($r, qr/ 206 /, 'range prev - 206 partial reply');
like($r, qr/^23$/m, 'range prev - correct content');
like($r, qr/Status: HIT/m, 'range prev - cache status');

$r = get('/cache/t?mrange', "Range: bytes=4-5");
like($r, qr/ 206 /, 'range next - 206 partial reply');
like($r, qr/^45$/m, 'range next - correct content');
like($r, qr/Status: HIT/m, 'range next - cache status');

$r = get('/cache/t?first', "Range: bytes=2-");
like($r, qr/ 206 /, 'first bytes - 206 partial reply');
like($r, qr/^23456789abcdef$/m, 'first bytes - correct content');
like($r, qr/Status: MISS/m, 'first bytes - cache status');

$r = get('/cache/t?first', "Range: bytes=4-");
like($r, qr/ 206 /, 'first bytes cached - 206 partial reply');
like($r, qr/^456789abcdef$/m, 'first bytes cached - correct content');
like($r, qr/Status: HIT/m, 'first bytes cached - cache status');

# multiple ranges
# we want 206, but 200 is also fine

$r = get('/cache/t?many', "Range: bytes=3-3,4-4");
like($r, qr/200 OK/, 'many - 206 partial reply');
like($r, qr/^0123456789abcdef$/m, 'many - correct content');

$r = get('/cache/t?last', "Range: bytes=-10");
like($r, qr/206 /, 'last bytes - 206 partial reply');
like($r, qr/^6789abcdef$/m, 'last bytes - correct content');

# respect not modified and range filters

my ($etag) = http_get('/t') =~ /ETag: (.*)/;

like(get('/cache/t?inm', "If-None-Match: $etag"), qr/ 304 /, 'inm');
like(get('/cache/t?inm', "If-None-Match: bad"), qr/ 200 /, 'inm bad');

like(get('/cache/t?im', "If-Match: $etag"), qr/ 200 /, 'im');
like(get('/cache/t?im', "If-Match: bad"), qr/ 412 /, 'im bad');

$r = get('/cache/t?if', "Range: bytes=3-4\nIf-Range: $etag");
like($r, qr/ 206 /, 'if-range - 206 partial reply');
like($r, qr/^34$/m, 'if-range - correct content');

# respect Last-Modified from non-cacheable response with If-Range

my ($lm) = http_get('/t') =~ /Last-Modified: (.*)/;
$r = get('/proxy/t', "Range: bytes=3-4\nIf-Range: $lm");
like($r, qr/ 206 /, 'if-range last-modified proxy - 206 partial reply');
like($r, qr/^34$/m, 'if-range last-modified proxy - correct content');

$r = get('/cache/t?ifb', "Range: bytes=3-4\nIf-Range: bad");
like($r, qr/ 200 /, 'if-range bad - 200 ok');
like($r, qr/^0123456789abcdef$/m, 'if-range bad - correct content');

# first slice isn't known

$r = get('/cache/t?skip', "Range: bytes=6-7\nIf-Range: $etag");
like($r, qr/ 206 /, 'if-range skip slice - 206 partial reply');
like($r, qr/^67$/m, 'if-range skip slice - correct content');

$r = get('/cache/t?skip', "Range: bytes=6-7\nIf-Range: $etag");
like($r, qr/ 206 /, 'if-range skip slice - cached - 206 partial reply');
like($r, qr/^67$/m, 'if-range skip slice - cached - correct content');
like($r, qr/HIT/, 'if-range skip bytes - cached - cache status');

$r = get('/cache/t?skip', "Range: bytes=2-3");
like($r, qr/ 206 /, 'if-range skip slice - skipped - 206 partial reply');
like($r, qr/^23$/m, 'if-range skip slice - skipped - correct content');
like($r, qr/MISS/, 'if-range skip bytes - skipped - cache status');

SKIP: {
	eval { require FCGI; };
	skip 'FCGI not installed', 5 if $@;
	skip 'win32', 5 if $^O eq 'MSWin32';

	$t->run_daemon(\&fastcgi_daemon);
	$t->waitforsocket('127.0.0.1:' . port(8082));

	like(http_get('/fastcgi'), qr/200 OK.*MISS.*^012345678$/ms, 'fastcgi');
	like(http_get('/fastcgi'), qr/200 OK.*HIT.*^012345678$/ms,
		'fastcgi cached');

	like(get("/fastcgi?1", "Range: bytes=0-0"), qr/ 206 .*MISS.*^0$/ms,
		'fastcgi slice');
	like(get("/fastcgi?1", "Range: bytes=1-1"), qr/ 206 .*HIT.*^1$/ms,
		'fastcgi slice cached');
	like(get("/fastcgi?1", "Range: bytes=2-2"), qr/ 206 .*MISS.*^2$/ms,
		'fastcgi slice next');
}

# slicing in named location

$r = http_get('/cache-redirect');

like($r, qr/ 200 .*^0123456789abcdef$/ms, 'in named location');
is(scalar @{[ glob $t->testdir() . '/cach3/*' ]}, 8,
	'in named location - cache entries');

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

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8082), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $body = '012345678';
	my $len = length($body);

	while ($request->Accept() >= 0) {
		my ($start, $stop) = $ENV{Range} =~ /bytes=(\d+)-(\d+)/;
		my $body = substr($body, $start, ($stop - $start) + 1);
		$stop = $len - 1 if $stop > $len - 1;

		print <<EOF;
Status: 206
Content-Type: text/html
Content-Range: bytes $start-$stop/$len

EOF

		print $body;
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
