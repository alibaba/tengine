#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for index module.

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

my $t = Test::Nginx->new()->has(qw/http/)->plan(14)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        add_header   X-URI $uri;

        location / {
            # index index.html by default
        }

        location /redirect/ {
            index /re.html;
        }

        location /loop/ {
            index /loop/;
        }

        location /no_index/ {
            alias %%TESTDIR%%/;
            index nonexisting.html;
        }

        location /many/ {
            alias %%TESTDIR%%/;
            index nonexisting.html many.html;
        }

        location /var/ {
            alias %%TESTDIR%%/;
            index $server_name.html;
        }

        location /va2/ {
            alias %%TESTDIR%%/;
            # before 1.13.8, the token produced emerg:
            # directive "index" is not terminated by ";"
            index ${server_name}.html;
        }

        location /var_redirect/ {
            index /$server_name.html;
        }

        location /not_found/ {
            error_log %%TESTDIR%%/log_not_found.log;

            location /not_found/off/ {
                error_log %%TESTDIR%%/off.log;
                log_not_found off;
            }
        }
    }
}

EOF

$t->write_file('index.html', 'body');
$t->write_file('many.html', 'manybody');
$t->write_file('re.html', 'rebody');
$t->write_file('localhost.html', 'varbody');

my $d = $t->testdir();
mkdir("$d/forbidden");
chmod(0000, "$d/forbidden");

$t->run();

###############################################################################

like(http_get('/'), qr/X-URI: \/index.html.*body/ms, 'default index');
like(http_get('/no_index/'), qr/403 Forbidden/, 'no index');
like(http_get('/redirect/'), qr/X-URI: \/re.html.*rebody/ms, 'redirect');
like(http_get('/loop/'), qr/500 Internal/, 'redirect loop');
like(http_get('/many/'), qr/X-URI: \/many\/many.html.*manybody/ms, 'many');
like(http_get('/var/'), qr/X-URI: \/var\/localhost.html.*varbody/ms, 'var');
like(http_get('/va2/'), qr/X-URI: \/va2\/localhost.html.*varbody/ms, 'var 2');
like(http_get('/var_redirect/'), qr/X-URI: \/localhost.html.*varbody/ms,
	'var with redirect');

like(http_get('/not_found/'), qr/404 Not Found/, 'not found');
like(http_get('/not_found/off/'), qr/404 Not Found/, 'not found log off');
like(http_get('/forbidden/'), qr/403 Forbidden/, 'directory access denied');
like(http_get('/index.html/'), qr/404 Not Found/, 'not a directory');

$t->stop();

like($t->read_file('log_not_found.log'), qr/error/, 'log_not_found');
unlike($t->read_file('off.log'), qr/error/, 'log_not_found off');

chmod(0700, "$d/forbidden");

###############################################################################
