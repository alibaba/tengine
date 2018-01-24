#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module with subrequests.

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
plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has(qw/http gunzip ssi proxy gzip_static/)
	->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

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
            gunzip on;
            gzip_vary on;
            proxy_pass http://127.0.0.1:8081/;
            proxy_set_header Accept-Encoding gzip;
        }

        location /t.html {
            ssi on;
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
$t->write_file('t.html', 'xxx <!--#include virtual="/t1" --> xxx');

$t->run();

###############################################################################

my $r = http_get('/t.html');
unlike($r, qr/Content-Encoding/, 'no content encoding');
like($r, qr/^xxx (X\d\d\dXXXXXX){100} xxx$/m, 'correct gunzipped response');

$r = http_gzip_request('/t.html');
unlike($r, qr/Content-Encoding/, 'gzip - no content encoding');
like($r, qr/(X\d\d\dXXXXXX){100}/m, 'gzip - correct gunzipped response');

###############################################################################
