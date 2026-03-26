#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache, proxy_cache_use_stale.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite limit_req ssi/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2  keys_zone=NAME:1m;

    limit_req_zone  $binary_remote_addr  zone=one:1m  rate=10r/m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /ssi.html {
            ssi on;
            sendfile_max_chunk  4k;
        }

        location /escape {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
            proxy_cache_background_update  on;
            add_header X-Cache-Status $upstream_cache_status;
        }

        location / {
            proxy_pass    http://127.0.0.1:8081;

            proxy_cache   NAME;

            proxy_cache_key  $uri;

            proxy_cache_revalidate  on;

            proxy_cache_background_update  on;

            add_header X-Cache-Status $upstream_cache_status;

            location /t4.html {
                proxy_pass    http://127.0.0.1:8081/t.html;

                proxy_cache_revalidate  off;
            }

            location /t5.html {
                proxy_pass    http://127.0.0.1:8081/t.html;

                proxy_cache_background_update  off;
            }

            location ~ /(reg)(?P<name>exp).html {
                proxy_pass    http://127.0.0.1:8081/$1$name.html;

                proxy_cache_background_update  on;
            }

            location /updating/ {
                proxy_pass    http://127.0.0.1:8081/;

                proxy_cache_use_stale  updating;
            }

            location /t7.html {
                proxy_pass    http://127.0.0.1:8081;

                sendfile_max_chunk  4k;
            }

            location /t8.html {
                proxy_pass    http://127.0.0.1:8081/t.html;

                proxy_cache_valid  1s;
            }

            if ($arg_if) {
                # nothing
            }
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        add_header Cache-Control $http_x_cache_control;

        if ($arg_lim) {
            set $limit_rate 1k;
        }

        if ($arg_e) {
            return 500;
        }

        location / { }

        location /t6.html {
            limit_req zone=one burst=2;
        }

        location /t9.html {
            add_header Cache-Control "max-age=1, stale-while-revalidate=10";
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->write_file('tt.html', 'SEE-THIS');
$t->write_file('t2.html', 'SEE-THIS');
$t->write_file('t3.html', 'SEE-THIS');
$t->write_file('t6.html', 'SEE-THIS');
$t->write_file('t7.html', 'SEE-THIS' x 1024);
$t->write_file('t9.html', 'SEE-THIS' x 1024);
$t->write_file('ssi.html', 'xxx <!--#include virtual="/t9.html" --> xxx');
$t->write_file('escape.html', 'SEE-THIS');
$t->write_file('regexp.html', 'SEE-THIS');

$t->run()->plan(34);

###############################################################################

like(get('/t.html', 'max-age=1, stale-if-error=5'), qr/MISS/, 'stale-if-error');
like(http_get('/t.html?e=1'), qr/HIT/, 's-i-e - cached');

like(get('/t2.html', 'max-age=1, stale-while-revalidate=10'), qr/MISS/,
	'stale-while-revalidate');
like(http_get('/t2.html'), qr/HIT/, 's-w-r - cached');

get('/tt.html', 'max-age=1, stale-if-error=3');
get('/t3.html', 'max-age=1, stale-while-revalidate=2');
get('/t4.html', 'max-age=1, stale-while-revalidate=3');
get('/t5.html', 'max-age=1, stale-while-revalidate=3');
get('/t6.html', 'max-age=1, stale-while-revalidate=4');
get('/t7.html', 'max-age=1, stale-while-revalidate=10');
http_get('/ssi.html');
get('/updating/t.html', 'max-age=1');
get('/updating/t2.html', 'max-age=1, stale-while-revalidate=2');
get('/updating/tt.html', 'max-age=1, stale-if-error=5');
get('/t8.html', 'stale-while-revalidate=10');
get('/escape.htm%6C', 'max-age=1, stale-while-revalidate=10');
get('/regexp.html', 'max-age=1, stale-while-revalidate=10');

sleep 2;

# stale 5xx response is ignored since 1.19.3,
# "proxy_cache_use_stale updating;" allows to get it still

like(http_get('/t.html?e=1'), qr/ 500 /, 's-i-e - stale 5xx ignore');
like(http_get('/tt.html?e=1'), qr/ 500 /, 's-i-e - stale 5xx ignore 2');
like(http_get('/updating/tt.html'), qr/STALE/, 's-i-e - stale 5xx updating');
like(http_get('/t.html'), qr/REVALIDATED/, 's-i-e - revalidated');

like(http_get('/t2.html?e=1'), qr/STALE/, 's-w-r - revalidate error');
like(http_get('/t2.html'), qr/STALE/, 's-w-r - stale while revalidate');
like(http_get('/t2.html'), qr/HIT/, 's-w-r - revalidated');

like(get('/t4.html', 'max-age=1, stale-while-revalidate=2'), qr/STALE/,
	's-w-r - unconditional revalidate');
like(http_get('/t4.html'), qr/HIT/, 's-w-r - unconditional revalidated');

like(http_get('/t5.html?e=1'), qr/ 500 /,
	's-w-r - foreground revalidate error');
like(http_get('/t5.html'), qr/REVALIDATED/, 's-w-r - foreground revalidated');

# proxy_pass to regular expression with named and positional captures

like(http_get('/regexp.html'), qr/STALE/, 's-w-r - regexp background update');
like(http_get('/regexp.html'), qr/HIT/, 's-w-r - regexp revalidated');

# UPDATING while s-w-r

$t->write_file('t6.html', 'SEE-THAT');

my $s = get('/t6.html', 'max-age=1, stale-while-revalidate=2', start => 1);
select undef, undef, undef, 0.2;
like(http_get('/t6.html'), qr/UPDATING.*SEE-THIS/s, 's-w-r - updating');
like(http_end($s), qr/STALE.*SEE-THIS/s, 's-w-r - updating stale');
like(http_get('/t6.html'), qr/HIT.*SEE-THAT/s, 's-w-r - updating revalidated');

# stale-while-revalidate with proxy_cache_use_stale updating

like(http_get('/updating/t.html'), qr/STALE/,
	's-w-r - use_stale updating stale');
like(http_get('/updating/t.html'), qr/HIT/,
	's-w-r - use_stale updating revalidated');

# stale-while-revalidate with proxy_cache_valid

like(http_get('/t8.html'), qr/STALE/, 's-w-r - proxy_cache_valid revalidate');
like(http_get('/t8.html'), qr/HIT/, 's-w-r - proxy_cache_valid revalidated');

sleep 2;

like(http_get('/t2.html?e=1'), qr/STALE/, 's-w-r - stale after revalidate');
like(http_get('/t3.html?e=1'), qr/ 500 /, 's-w-r - ceased');
like(http_get('/tt.html?e=1'), qr/ 500 /, 's-i-e - ceased');
like(http_get('/updating/t2.html'), qr/STALE/,
	's-w-r - overriden with use_stale updating');

# stale response not blocked by background update.
# before 1.13.1, if stale response was not sent in one pass, its remaining
# part was blocked and not sent until background update has been finished

$t->write_file('t7.html', 'SEE-THAT' x 256);

my $r = read_all(get('/t7.html?lim=1', 'max-age=1', start => 1));
like($r, qr/STALE.*^(SEE-THIS){1024}$/ms, 's-w-r - stale response not blocked');

$t->write_file('t9.html', 'SEE-THAT' x 256);
$t->write_file('ssi.html', 'xxx <!--#include virtual="/t9.html?lim=1" --> xxx');

$r = read_all(http_get('/ssi.html', start => 1));
like($r, qr/^xxx (SEE-THIS){1024} xxx$/ms, 's-w-r - not blocked in subrequest');

# due to the missing content_handler inheritance in a cloned subrequest,
# this used to access a static file in the update request

like(http_get('/t2.html?if=1'), qr/STALE/, 'background update in if');
like(http_get('/t2.html?if=1'), qr/HIT/, 'background update in if - updated');

# ticket #1430, uri escaping in cloned subrequests

$t->write_file('escape.html', 'SEE-THAT');

get('/escape.htm%6C', 'max-age=1');

like(http_get('/escape.htm%6C'), qr/HIT/, 'escaped after escaped');
like(http_get('/escape.html'), qr/MISS/, 'unescaped after escaped');

###############################################################################

sub get {
	my ($url, $extra, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.1
Host: localhost
Connection: close
X-Cache-Control: $extra

EOF
}

# background update is known to postpone closing connection with client

sub read_all {
	my ($s) = @_;
	my $r = '';
	while (IO::Select->new($s)->can_read(1)) {
		$s->sysread(my $buf, 8192) or last;
		log_in($buf);
		$r .= $buf;
	}
	return $r;
}

###############################################################################
