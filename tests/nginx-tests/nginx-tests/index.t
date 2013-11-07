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

my $t = Test::Nginx->new()->has(qw/http/)->plan(7)
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

        location /var_redirect/ {
            index /$server_name.html;
        }
    }
}

EOF

$t->write_file('index.html', 'body');
$t->write_file('many.html', 'manybody');
$t->write_file('re.html', 'rebody');
$t->write_file('localhost.html', 'varbody');

$t->run();

###############################################################################

like(http_get('/'), qr/X-URI: \/index.html.*body/ms, 'default index');
like(http_get('/no_index/'), qr/403 Forbidden/, 'no index');
like(http_get('/redirect/'), qr/X-URI: \/re.html.*rebody/ms, 'redirect');
like(http_get('/loop/'), qr/500 Internal/, 'redirect loop');
like(http_get('/many/'), qr/X-URI: \/many\/many.html.*manybody/ms, 'many');
like(http_get('/var/'), qr/X-URI: \/var\/localhost.html.*varbody/ms, 'var');
like(http_get('/var_redirect/'), qr/X-URI: \/localhost.html.*varbody/ms,
	'var with redirect');

###############################################################################
