#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for predicate locations, additional tests.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy map/);

plan(skip_all => 'not yet') unless $t->has_version('1.31.5');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $uri $mapped {
        /mapped  1;
    }

    map $uri $volatile {
        volatile;
        /volatile  1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location $arg_proxy {
            proxy_pass http://127.0.0.1:8081;
        }

        location $arg_file {
            root %%TESTDIR%%/html;
        }

        location $arg_alias_var {
            alias %%TESTDIR%%/html$uri;
        }

        location $arg_alias_try {
            alias %%TESTDIR%%/html/;
            try_files $uri =404;
        }

        location $arg_alias_nest {
            location /sub/ {
                alias %%TESTDIR%%/html/;
            }
            return 204;
        }

        location $arg_dir {
            location /dir/ {
                proxy_pass http://127.0.0.1:8081;
            }
        }

        location /redirect/mapped {
            rewrite ^ /mapped last;
        }

        location /redirect/volatile {
            rewrite ^ /volatile last;
        }

        location $mapped {
            add_header X-Location "mapped";
            return 204;
        }

        location $volatile {
            add_header X-Location "volatile";
            return 204;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Location "proxied";
            return 204;
        }
    }
}

EOF

mkdir($t->testdir() . '/html');
$t->write_file('html/t', 'SEE-THIS');

$t->run()->plan(11);

###############################################################################

like(http_get('/some/path?proxy=1'), qr/X-Location: proxied/,
	'proxy_pass in predicate location');
like(http_get('/t?file=1'), qr/SEE-THIS/, 'root in predicate location');

like(http_get('/t?alias_var=1'), qr/SEE-THIS/,
	'alias with variables in predicate location - uri');

like(http_get('/t?alias_try=1'), qr/SEE-THIS/,
	'alias with try_files in predicate location');

like(http_get('/sub/t?alias_nest=1'), qr/SEE-THIS/,
	'alias in nested prefix under predicate location');

like(http_get('/dir/?dir=1'), qr/X-Location: proxied/,
	'slash prefix in predicate location');

like(http_get('/dir?dir=1'), qr/301 Moved/,
	'auto redirect in predicate location');

like(http_get('/mapped'), qr/X-Location: mapped/, 'map predicate');
like(http_get('/volatile'), qr/X-Location: volatile/, 'volatile map predicate');

like(http_get('/redirect/mapped'), qr/404 Not Found/,
	'map predicate cached before redirect');
like(http_get('/redirect/volatile'), qr/X-Location: volatile/,
	'volatile map after redirect');

###############################################################################
