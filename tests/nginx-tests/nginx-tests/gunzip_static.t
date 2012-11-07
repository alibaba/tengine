#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module with gzip_static always.  It is basically
# the copy of gunzip.t with minor modifications.

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

my $t = Test::Nginx->new()->has(qw/http gunzip proxy gzip_static rewrite/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

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
            gzip_static always;
        }
        location = /double {
            error_page 404 @double;
            gzip_static on;
        }
        location @double {
            rewrite ^ /t1 break;
            gunzip on;
            gzip_static always;
        }
        location /error {
            error_page 500 /t1;
            return 500;
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

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no gzip_static always') if $@;

$t->plan(12);

###############################################################################

pass('runs');

like(http_get('/t1'), qr/(?!Content-Encoding).*^(X\d\d\dXXXXXX){100}$/m,
	'correct gunzipped response');
like(http_gzip_request('/t1'), qr/Content-Encoding: gzip.*\Q$out\E/ms,
	'gzip still works');

like(http_get('/double'), qr/(?!Content-Encoding).^(X\d\d\dXXXXXX){100}$/ms,
	'gunzip with gzip_tested');
like(http_gzip_request('/double'), qr/Content-Encoding: gzip.*\Q$out\E/ms,
	'gzip still works with gzip_tested');

like(http_get('/t2'), qr/^(X\d\d\dXXXXXX){200}$/m, 'multiple gzip members');

like(http_get('/error'), qr/^(X\d\d\dXXXXXX){100}$/m, 'errors gunzipped');

unlike(http_head('/t1'), qr/Content-Encoding/, 'head - no content encoding');

like(http_get('/t1'), qr/Vary/, 'get vary');
like(http_head('/t1'), qr/Vary/, 'head vary');
unlike(http_get('/t3'), qr/Vary/, 'no vary on non-gzipped get');
unlike(http_head('/t3'), qr/Vary/, 'no vary on non-gzipped head');

###############################################################################
