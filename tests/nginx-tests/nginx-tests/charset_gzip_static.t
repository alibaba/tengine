#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for charset filter.

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

my $t = Test::Nginx->new()->has(qw/http charset gzip_static/)->plan(13)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html html;
    }

    charset_map B A {
        58 59; # X -> Y
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            charset utf-8;
            gzip_static on;
        }

        location /t2 {
            gzip_static on;
            charset A;
            source_charset B;
        }

        location /t {
            gzip_static on;
        }

        location /p/ {
            charset utf-8;
            proxy_pass http://127.0.0.1:8080/;
            proxy_http_version 1.1;
        }

        location /p.ab/ {
            charset A;
            source_charset B;
            proxy_pass http://127.0.0.1:8080/;
            proxy_http_version 1.1;
        }

        location /p.aa/ {
            charset A;
            source_charset A;
            proxy_pass http://127.0.0.1:8080/;
            proxy_http_version 1.1;
        }
    }
}

EOF

$t->write_file('t1.html', '');
$t->write_file('t1.html.gz', '');

my $in = 'X' x 99;
my $out;

eval {
	require IO::Compress::Gzip;
	IO::Compress::Gzip::gzip(\$in => \$out);
};

$t->write_file('t2.html', $in);
$t->write_file('t2.html.gz', $out);

$t->write_file('t.html', '');
$t->write_file('t.html.gz', '');

###############################################################################

# charset filter currently ignores responses with Content-Encoding set
# (except ones with r->ignore_content_encoding used by gzip_static)
# as it can't convert such content; there are two problems though:
#
# - it make sense to indicate charset
#   if conversion isn't needed
#
# - gzip_static may need conversion, too
#
# proper solution seems to be to always allow charset indication, but
# don't try to do anything if recoding is needed

like(http_get('/t1.html'), qr!text/html; charset=!, 'plain');
like(http_gzip_request('/t1.html'), qr!text/html; charset=.*gzip!ms, 'gzip');

like(http_get('/t2.html'), qr!text/html; charset=A.*Y{99}!ms, 'recode plain');
like(http_gzip_request('/t2.html'), qr!text/html\x0d.*gzip!ms, 'recode gzip');
http_gzip_like(http_gzip_request('/t2.html'), qr!X{99}!, 'recode content');

like(http_get('/t.html'), qr!text/html\x0d!, 'nocharset plain');
like(http_gzip_request('/t.html'), qr!text/html\x0d.*gzip!ms, 'nocharset gzip');

like(http_get('/p/t.html'), qr!text/html; charset=!, 'proxy plain');
like(http_gzip_request('/p/t.html'), qr!text/html; charset=.*gzip!ms,
	'proxy gzip');

like(http_get('/p.ab/t.html'), qr!text/html; charset=A!ms,
	'proxy recode plain');
like(http_gzip_request('/p.ab/t.html'), qr!text/html\x0d.*gzip!ms,
	'proxy recode gzip');

like(http_get('/p.aa/t.html'), qr!text/html; charset=A!ms,
	'proxy nullrecode plain');
like(http_gzip_request('/p.aa/t.html'), qr!text/html; charset=A.*gzip!ms,
	'proxy nullrecode gzip');

###############################################################################
