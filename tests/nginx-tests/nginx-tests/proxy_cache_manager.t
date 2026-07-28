#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache, manager parameters.

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

plan(skip_all => 'long test') unless $ENV{TEST_NGINX_UNSAFE};

plan(skip_all => 'page size is not appropriate') unless
	POSIX::sysconf(&POSIX::_SC_PAGESIZE) == 4096;

my $t = Test::Nginx->new()->has(qw/http proxy cache/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  max_size=0  keys_zone=NAME:1m
                       manager_sleep=5  manager_files=2  manager_threshold=10;

    proxy_cache_path   %%TESTDIR%%/water  keys_zone=NAM2:16k
                       manager_sleep=5;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_valid   any   1m;
        }

        location /water/ {
            proxy_pass    http://127.0.0.1:8081/t.html;
            proxy_cache   NAM2;

            proxy_cache_valid   any   1m;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run()->plan(3);

###############################################################################

my $d = $t->testdir();

# wait for cache manager start

sleep 1;

http_get("/t.html?$_") for (1 .. 5);

# pretend we could not fit into zone

http_get("/water/?$_") for (1 .. 100);

my $n = files("$d/water");

# wait for cache manager process

sleep 10;

cmp_ok(files("$d/water"), '<', $n, 'manager watermark');

is(files("$d/cache"), 3, 'manager files');

sleep 5;

is(files("$d/cache"), 1, 'manager sleep');

###############################################################################

sub files {
	my ($path) = @_;
	my $dh;

	opendir($dh, $path);
	return scalar grep { ! /^\./ } readdir($dh);
}

###############################################################################
