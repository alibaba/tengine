#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gzip filter module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http gzip perl/)->plan(2);

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

        gzip on;
        gzip_min_length 0;

        location / {
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;
                $r->print("DA");
                $r->flush();
                $r->flush();
                $r->print("TA");
                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/'), qr/DATA/, 'request with flush');

TODO: {
local $TODO = 'not yet';

# gzip filter doesn't properly handle empty flush buffers, see
# http://nginx.org/pipermail/nginx/2010-November/023693.html

http_gzip_like(http_gzip_request('/'), qr/DATA/, 'gzip request with flush');

}

###############################################################################
