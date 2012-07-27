#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx ssi module, waited subrequests.

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

my $t = Test::Nginx->new()->has(qw/http ssi/)->plan(2);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            ssi on;
        }
    }
}

EOF

$t->write_file('index.html', 'x<!--#include virtual="/first.html" -->' .
	'x<!--#include virtual="/second.html" -->x');
$t->write_file('first.html', 'FIRST');
$t->write_file('second.html',
	'<!--#include virtual="/waited.html" wait="yes"-->xSECOND');
$t->write_file('waited.html', 'WAITED');

$t->run();

###############################################################################

like(http_get('/'), qr/^xFIRSTxWAITEDxSECONDx$/m, 'waited non-active');

like(`grep -F '[alert]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no alerts');

###############################################################################
