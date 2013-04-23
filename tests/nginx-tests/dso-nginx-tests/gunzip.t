#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module.

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

eval { require IO::Compress::Gzip; };
Test::More::plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has(qw/http gunzip proxy gzip_static/)->plan(13);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

%%TEST_GLOBALS_DSO%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            gunzip on;
            gzip_vary on;
            proxy_pass http://127.0.0.1:8081/;
            proxy_set_header Accept-Encoding gzip;
        }
        location /error {
            error_page 500 /t1;
            return 500;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            default_type text/plain;
            gzip_static on;
            gzip_http_version 1.0;
            gzip_types text/plain;
        }
    }
}

EOF

my $in = join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99));
my $out;

IO::Compress::Gzip::gzip(\$in => \$out);

$t->write_file('t1.gz', $out);
$t->write_file('t2.gz', $out . $out);
$t->write_file('t3', 'not compressed');

my $emptyin = '';
my $emptyout;
IO::Compress::Gzip::gzip(\$emptyin => \$emptyout);

$t->write_file('empty.gz', $emptyout);

$t->run();

###############################################################################

pass('runs');

my $r = http_get('/t1');
unlike($r, qr/Content-Encoding/, 'no content encoding');
like($r, qr/^(X\d\d\dXXXXXX){100}$/m, 'correct gunzipped response');

$r = http_gzip_request('/t1');
like($r, qr/Content-Encoding: gzip/, 'gzip still works - encoding');
like($r, qr/\Q$out\E/, 'gzip still works - content');

like(http_get('/t2'), qr/^(X\d\d\dXXXXXX){200}$/m, 'multiple gzip members');

like(http_get('/error'), qr/^(X\d\d\dXXXXXX){100}$/m, 'errors gunzipped');

unlike(http_head('/t1'), qr/Content-Encoding/, 'head - no content encoding');

like(http_get('/t1'), qr/Vary/, 'get vary');
like(http_head('/t1'), qr/Vary/, 'head vary');
unlike(http_get('/t3'), qr/Vary/, 'no vary on non-gzipped get');
unlike(http_head('/t3'), qr/Vary/, 'no vary on non-gzipped head');

like(http_get('/empty'), qr/ 200 /, 'gunzip empty');

###############################################################################
