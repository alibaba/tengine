#!/usr/bin/perl

###############################################################################

use warnings;
use strict;

use File::Copy;
use File::Basename;
use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http slice/)->plan(23);

$t->set_dso("ngx_http_slice_module", "ngx_http_slice_module.so");
$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;
	gzip    on;
        
        location / {
            slice;
        }

        location /names {
            slice;
            slice_arg_begin start;
            slice_arg_end   stop;
        }

        location /hf {
            slice;
            slice_header header;
            slice_footer footer;
        }

        location /hnf {
            slice;
            slice_header header;
            slice_header_first off;
        }

        location /fnl {
            slice;
            slice_footer footer;
            slice_footer_last off;
        }
    }
}

EOF

$t->write_file('demo.txt', 'ZJQW');

my $d = $t->testdir();
mkdir("$d/names");
$t->write_file('names/demo.txt', 'ZJQW');

$d = $t->testdir();
mkdir("$d/hf");
$t->write_file('hf/demo.txt', 'ZJQW');

$d = $t->testdir();
mkdir("$d/hnf");
$t->write_file('hnf/demo.txt', 'ZJQW');

$d = $t->testdir();
mkdir("$d/fnl");
$t->write_file('fnl/demo.txt', 'ZJQW');

$t->run();

###############################################################################


like(http_get('/demo.txt?begin=0&end=2'), qr/ZJ/, '[0, ');
like(http_get('/demo.txt?begin=1&end=2'), qr/J/, '[1, 2)');
like(http_get('/demo.txt?begin=0&end=4'), qr/ZJQW/, '[0, 4)');
like(http_get('/demo.txt?begin=2&end=1'), qr/QW/, 'begin > end => [begin, END)');
like(http_get('/demo.txt?begin=1'), qr/JQW/, 'without end =>, [begin, END)');
like(http_get('/demo.txt?end=2'), qr/ZJ/, 'without begin =>, [BEGIN, end)');
like(http_get('/demo.txt?begin=5&end=1000'), qr/ZJ/, 'begin is greater than file size =>, [BEGIN, end)');
like(http_get('/demo.txt?begin=1&end=1000'), qr/JQW/, 'end is greater than file size => [begin, end)');
like(http_get('/demo.txt?begin=-1&end=2'), qr/ZJ/, 'begin is negative =>, [BEGIN, end)');
like(http_get('/demo.txt?begin=abc&end=2'), qr/ZJ/, 'begin is not numeric =>, [BEGIN, end)');
like(http_get('/demo.txt?begin=1&end=-2'), qr/JQW/, 'end is negative =>, [begin, END)');
like(http_get('/demo.txt?begin=1&end=abc'), qr/JQW/, 'end is not numeric =>, [begin, END)');
like(http_get('/demo.txt?begin=abc&end=def'), qr/ZJQW/, 'both begin and end are invalid =>, [BEGIN, END)');
like(http_get('/demo.txt?begin=1&end=1'), qr/Content-Length: 0/, 'begin is equal to end => 0');

like(http_get('/names/demo.txt?start=0&stop=2'), qr/ZJ/, 'rename argument names');

like(http_get('/hf/demo.txt?begin=0&end=2'), qr/headerZJfooter/, 'header first');
like(http_get('/hf/demo.txt?begin=1&end=4'), qr/headerJQWfooter/, 'footer last');
like(http_get('/hf/demo.txt?begin=1&end=2'), qr/headerJfooter/, 'with header and footer');
like(http_get('/hf/demo.txt?begin=2&end=2'), qr/Content-Length: 0/, 'header & footer, zero length');

like(http_get('/hnf/demo.txt?begin=0&end=2'), qr/ZJ/, 'header without first');
like(http_get('/hnf/demo.txt?begin=1&end=2'), qr/headerJ/, 'header without first (normal)');

like(http_get('/fnl/demo.txt?begin=1&end=4'), qr/JQW/, 'footer without last');
like(http_get('/fnl/demo.txt?begin=1&end=2'), qr/Jfooter/, 'footer without last (normal)');


###############################################################################
