#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for subrequest_output_buffer_size directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy ssi/)->plan(4)
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

        location / {
            proxy_pass http://127.0.0.1:8081;
            subrequest_output_buffer_size 42;
        }

        location /longok {
            proxy_pass http://127.0.0.1:8081/long;
        }

        location /ssi {
            ssi on;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('ssi.html',
	'<!--#include virtual="/$arg_c" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->write_file('length', 'TEST-OK-IF-YOU-SEE-THIS');
$t->write_file('long', 'x' x 400);
$t->write_file('empty', '');

$t->run();

###############################################################################

my ($r, $n);

like(http_get('/ssi.html?c=length'), qr/SEE-THIS/, 'request');
like(http_get('/ssi.html?c=empty'), qr/set: $/, 'empty');
unlike(http_get('/ssi.html?c=long'), qr/200 OK/, 'long');
like(http_get('/ssi.html?c=longok'), qr/x{400}/, 'long ok');

###############################################################################
