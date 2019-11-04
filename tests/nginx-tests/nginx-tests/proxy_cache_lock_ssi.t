#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache lock with subrequests.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache ssi/)
	->write_file_expand('nginx.conf', <<'EOF')->plan(2);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    limit_req_zone $binary_remote_addr zone=one:1m rate=1r/m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
            proxy_cache_lock_timeout 100ms;

            proxy_read_timeout 3s;
        }

        location = /ssi.html {
            ssi on;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        limit_req zone=one burst=5;
    }

}

EOF

$t->write_file('ssi.html',
	'<!--#include virtual="/active" -->' .
	'<!--#include virtual="/locked" -->' .
	'end'
);

$t->write_file('active', 'active');
$t->write_file('locked', 'locked');

$t->run();

###############################################################################

# problem: if proxy cache lock wakeup happens in an inactive
# subrequest, just a connection write event may not trigger any
# further work

# main request -> subrequest /active (waiting for a backend),
#              -> subrequest /locked (locked by another request)

# this doesn't result in an infinite timeout as second subrequest
# is woken up by the postpone filter once first subrequest completes,
# but this is suboptimal behaviour

http_get('/charge');
my $start = time();

my $s = http_get('/locked', start => 1);
select undef, undef, undef, 0.2;

like(http_get('/ssi.html'), qr/end/, 'cache lock ssi');
http_end($s);
cmp_ok(time() - $start, '<=', 5, 'parallel execution after lock timeout');

###############################################################################
