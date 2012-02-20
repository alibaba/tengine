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

my $t = Test::Nginx->new()->has(qw/http/)->plan(58);
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    include mime.types;
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location / {
            concat  on;
            concat_types text/html text/css;

            gzip    on;
        }

        location /noconcat/ {
            concat off;
        }

        location /cssjs/ {
            concat on;
        }

        location /unique/ {
            concat on;
            concat_unique off;
        }
    }
}

EOF

$t->write_file('t1.html', 'one');
$t->write_file('t2.html', 'two');
$t->write_file('t3.html', 'three');
$t->write_file('t4.html', 'four');
$t->write_file('t5.html', 'five');
$t->write_file('t6.html', 'six');
$t->write_file('t7.html', 'seven');
$t->write_file('t8.html', 'eight');
$t->write_file('t9.html', 'nine');
$t->write_file('t10.html', 'ten');
$t->write_file('t11.html', 'eleven');
$t->write_file('ta.htm', 'ta');
$t->write_file('tb.shtml', 'tb');
$t->write_file('a.js', 'javascripta');
$t->write_file('b.js', 'javascriptb');
$t->write_file('foo.css', 'css1');
$t->write_file('bar.css', 'css2');
$t->write_file('empty.html', '');
$t->write_file('s1', 'ns1');
$t->write_file('s2', 'ns2');

my $d = $t->testdir();

mkdir("$d/dir1");
$t->write_file('dir1/hello.html', 'hello');

mkdir("$d/dir2");
$t->write_file('dir2/world.html', 'world');

mkdir("$d/dir3");
$t->write_file('dir3/c1.html', 'concat1');
$t->write_file('dir3/c2.html', 'concat2');
$t->write_file('dir3/c3.html', 'concat3');

mkdir("$d/noconcat");
$t->write_file('noconcat/n1.html', 'no1');
$t->write_file('noconcat/n2.html', 'no2');

mkdir("$d/cssjs");
$t->write_file('cssjs/1.css', 'css1');
$t->write_file('cssjs/2.css', 'css2');
$t->write_file('cssjs/1.js', 'js1');
$t->write_file('cssjs/2.js', 'js2');
$t->write_file('cssjs/1.html', 'html1');
$t->write_file('cssjs/2.html', 'html2');

mkdir("$d/unique");
$t->write_file('unique/1.css', 'css1');
$t->write_file('unique/2.css', 'css2');
$t->write_file('unique/1.js', 'js1');
$t->write_file('unique/2.js', 'js2');

my $m;
$m = dirname(dirname($ENV{TEST_NGINX_BINARY})) . '/conf/mime.types';
copy($m, $t->testdir()) or die 'copy mime.types failed: $!';

$t->run();

###############################################################################

my $r;

like(http_get('/?'), qr/403/, 'one question mark');
like(http_get('/??'), qr/403/, 'two question marks');
like(http_get('/???'), qr/400/, 'three question marks');
like(http_get('/????'), qr/400/, 'four question marks');
like(http_get('/??t1.html'), qr/one/, 'concat - one file');
like(http_get('/??t1.html,'), qr/one/, 'concat - one more comma');
like(http_get('/??t1.html,,'), qr/400/, 'concat - two more commas');
like(http_get('/??t1.html,,,'), qr/400/, 'concat - thre more commas');
like(http_get('/??t1.html,,t2.html'), qr/400/, 'concat - with one more comma');
like(http_get('/??t1.html,,,t2.html'), qr/400/, 'concat - with two more commas');

$r = http_get('/??t1.html,t2.html');
like($r, qr/onetwo/, 'concat - two files');
like($r, qr/^Content-Type: text\/html/m, 'concat - content type');

$r = http_get('/??t1.html,ta.htm,tb.shtml');
like($r, qr/onetatb/, 'concat - 3 different suffixes');
like($r, qr/^Content-Type: text\/html/m, 'concat - html type');

$r = http_get('/??a.js,b.js');
like($r, qr/javascriptajavascriptb/, 'concat - two javascript files');
like($r, qr/^Content-Type: application\/x-javascript/m, 'concat - content type (javascript)');

$r = http_get('/??foo.css,bar.css');
like($r, qr/css1css2/, 'concat - two css files');
like($r, qr/^Content-Type: text\/css/m, 'concat - content type (css)');

$r = http_get('/??s1,s2');
like($r, qr/400/, 'concat - no suffix');

like(http_get('/??t1.html,empty.html,t2.html'), qr/onetwo/, 'concat - empty file in middle');
like(http_get('/??empty.html,t1.html'), qr/one/, 'concat - empty file first');
like(http_get('/??t1.html,empty.html'), qr/one/, 'concat - empty file last');

$r = http_get('/??t1.html,t2.html,t3.html');
like($r, qr/onetwothree/, 'concat - thre files');
like($r, qr/^Content-Length: 11/m, 'concat - content length');

$r = http_get('/cssjs/??1.css,2.css');
like($r, qr/css1css2/, 'concat - css files (default)');
like($r, qr/^Content-Type: text\/css/m, 'concat - content type (default css)');

$r = http_get('/cssjs/??1.js,2.js');
like($r, qr/js1js2/, 'concat - js files (default)');
like($r, qr/^Content-Type: application\/x-javascript/m, 'concat - content type (default js)');

$r = http_get('/cssjs/??1.html,2.html');
like($r, qr/400/, 'concat - html files (default not support)');

$r = http_get('/cssjs/??1.js,1.css');
like($r, qr/400/, 'concat - mixed content types');

like(http_get('/??t1.html,t2.html,t100.html'), qr/404/, 'concat - has not found file');
like(http_get('/??t1.html,'), qr/one/, 'concat - one file and ","');
like(http_get('/??t1.html,t2.html,'), qr/onetwo/, 'concat - two files and ","');
like(http_get('/??t1.html?t=20100524'), qr/one/, 'concat - timestamp');
like(http_get('/??t1.html,t2.html?t=20100524'), qr/onetwo/, 'concat - timestamp 2');
like(http_get('/??t1.html,../t2.html'), qr/400/, 'concat - bad request (../)');
like(http_get('/??t1.html,./t2.html'), qr/onetwo/, 'concat - dot slash (./)');
like(http_get('/??t1.html,./../t2.html'), qr/400/, 'concat - bad request (/../)');
like(http_get('/??t1.html,/////../t2.html'), qr/400/, 'concat - bad request (/////../)');
like(http_get('/??../t1.html'), qr/400/, 'concat - bad request (../)');
like(http_get('/??t1.html, ../../../t2.html'), qr/400/, 'concat - bad request(../../../)');
like(http_get('/??t1.html,t2.html,t3.html,t4.html,t5.html,t6.html,t7.html,t8.html,t9.html,t10.html'),
     qr/onetwothreefourfivesixseveneightnineten/, 'concat - max files (default = 10)');
like(http_get('/??t1.html,t2.html,t3.html,t4.html,t5.html,t6.html,t7.html,t8.html,t9.html,t10.html,t11.html'),
     qr/400/, 'concat - max files (> default)');
like(http_get('/??t1.html,dir1/hello.html'), qr/onehello/, 'concat - with directory');
like(http_get('/??t1.html,dir1/hello.html,dir2/world.html'), qr/onehelloworld/, 'concat - with two directories');
like(http_get('/??dir1/hello.html,t1.html'), qr/helloone/, 'concat - directory first');
like(http_get('/??t1.html,/dir1/hello.html'), qr/onehello/, 'concat - directory starts with slash');
like(http_get('/??t1.html,//dir1/hello.html'), qr/onehello/, 'concat - directory starts with two slashes');
like(http_get('/??t1.html,///dir1/hello.html'), qr/onehello/, 'concat - directory starts with three slashes');
like(http_get('/??/dir1/hello.html,t1.html'), qr/helloone/, 'concat - directory starts with slash 2');
like(http_get('/dir3/??c1.html,c2.html,c3.html'), qr/concat1concat2concat3/, 'concat - under some directory');
like(http_get('/noconcat/??n1.html,n2.html'), qr/403/, 'concat - turn off');
like(http_get('/unique/??1.js,2.js'), qr/js1js2/, 'concat - unique off');
like(http_get('/unique/??1.css,2.css'), qr/css1css2/, 'concat - unique off 2');
like(http_get('/unique/??1.js,2.css'), qr/js1css2/, 'concat - unique off 3');
like(http_get('/unique/??1.css,2.js'), qr/css1js2/, 'concat - unique off 4');

$r = http_gzip_request('/??t1.html,t2.html,t3.html,t4.html,t5.html,t6.html');
like($r, qr/^Content-Encoding: gzip/m, 'gzip');
http_gzip_like($r, qr/onetwothreefourfivesix/, 'gzip content correct');

###############################################################################
