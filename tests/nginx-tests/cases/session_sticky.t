#! /usr/bin/perl

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;


select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(38);
$t->write_file_expand('9000', '9000');
$t->write_file_expand('9001', '9001');
$t->write_file_expand('9002', '9002');
$t->write_file_expand('9003', '9003');
$t->write_file_expand('hava_cookie', 'have_cookie');
$t->write_file_expand('no_have_cookie', 'no_have_cookie');

my $d = $t->testdir();
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream insert_indirect {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=insert option=indirect fallback=on;

        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream rewrite {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=rewrite fallback=on;
        server          127.0.0.1:9001;
        server          127.0.0.1:9000;
    }

    upstream rewrite_no_setcookie {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=rewrite fallback=on;
        server          127.0.0.1:9002;
        server          127.0.0.1:9003;
    }

    upstream prefix {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=prefix fallback=on;
        server          127.0.0.1:9001;
        server          127.0.0.1:9000;
    }

    upstream prefix_no_setcookie {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=prefix fallback=on;
        server          127.0.0.1:9002;
        server          127.0.0.1:9003;
    }

    upstream insert_indirect_off {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=insert option=indirect fallback=off;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_off {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=insert fallback=off;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream rewrite_off {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=rewrite fallback=off;
        server          127.0.0.1:9001;
        server          127.0.0.1:9000;
    }

    upstream prefix_off {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=prefix fallback=off;
        server          127.0.0.1:9001;
        server          127.0.0.1:9000;
    }

    upstream insert_nodomain {
        session_sticky cookie=test path=/ maxage=120 maxidle=40 maxlife=60 mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_nopath {
        session_sticky cookie=test maxage=120 maxidle=40 maxlife=60 mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_nomaxage {
        session_sticky cookie=test maxidle=40 maxlife=60 mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_nomaxlife {
        session_sticky cookie=test mode=insert option=indirect maxidle=400 fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_nomaxidle {
        session_sticky cookie=test mode=insert  fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream nothing {
        session_sticky cookie=test;
        server         127.0.0.1:9002;
        server         127.0.0.1:9003;
    }

    upstream insert_nocookie {
        session_sticky mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream nocookie {
        session_sticky cookie=test option=indirect;
        server 127.0.0.1:9004;
    }

    upstream havecookie {
        session_sticky cookie=test;
        server 127.0.0.1:9004;
    }

    upstream hash {
        session_sticky cookie=test domain=.taobao.com path=/ maxage=120 maxidle=40 maxlife=60 mode=insert fallback=on hash=plain;
        server          127.0.0.1:9002 id=9002;
        server          127.0.0.1:9003 id=9003;
    }

    server {
        listen     127.0.0.1:9000;
        location / {
            add_header  Set-Cookie test=test1234;
            index       9000;
        }
    }

    server {
        listen     127.0.0.1:9001;
        location / {
            add_header Set-Cookie test=test1234;
            index       9001;
        }
    }

    server {
        listen     127.0.0.1:9002;
        location / {
            index       9002;
        }
    }

    server {
        listen     127.0.0.1:9003;
        location / {
            index       9003;
        }
    }

    server {
        listen    127.0.0.1:9004;
        location / {
            if ($cookie_test != "") {
                return 401;
            }

            return 200;
        }
    }

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /test_insert_indirect {
            session_sticky_hide_cookie upstream=insert_indirect;
            proxy_pass  http://insert_indirect/;
        }

        location /test_hash {
            session_sticky_hide_cookie upstream=hash;
            proxy_pass http://hash/;
        }

        location /test_insert {
            session_sticky_hide_cookie upstream=insert;
            proxy_pass  http://insert/;
        }

        location /test_rewrite {
            session_sticky_hide_cookie upstream=rewrite;
            proxy_pass  http://rewrite/;
        }

        location /test_rewrite_no_setcookie {
            session_sticky_hide_cookie upstream=rewrite_no_setcookie;
            proxy_pass http://rewrite_no_setcookie/;
        }

        location /test_prefix {
            session_sticky_hide_cookie upstream=prefix;
            proxy_pass  http://prefix/;
        }

        location /test_prefix_no_setcookie {
            session_sticky_hide_cookie upstream=prefix_no_setcookie;
            proxy_pass http://prefix_no_setcookie/;
        }

        location /test_insert_indirect_off {
            session_sticky_hide_cookie upstream=insert_indirect_off;
            proxy_pass http://insert_indirect_off/;
        }

        location /test_insert_off {
            session_sticky_hide_cookie upstream=insert_off;
            proxy_pass http://insert_off/;
        }
        location /test_rewrite_off {
            session_sticky_hide_cookie upstream=rewrite_off;
            proxy_pass http://rewrite_off/;
        }

        location /test_prefix_off {
            session_sticky_hide_cookie upstream=prefix_off;
            proxy_pass http://prefix_off/;
        }

        location /test_insert_nodomain {
            session_sticky_hide_cookie upstream=insert_nodomain;
            proxy_pass http://insert_nodomain/;
        }

        location /test_insert_nopath {
            session_sticky_hide_cookie upstream=insert_nopath;
            proxy_pass http://insert_nopath/;
        }

        location /test_insert_nomaxage {
            session_sticky_hide_cookie upstream=insert_nomaxage;
            proxy_pass http://insert_nomaxage/;
        }

        location /test_insert_nomalife {
            session_sticky_hide_cookie upstream=insert_nomaxlife;
            proxy_pass http://insert_nomaxlife/;
        }
        location /test_insert_nomaxidle {
            session_sticky_hide_cookie upstream=insert_nomaxidle;
            proxy_pass http://insert_nomaxidle/;
        }

        location /test_insert_nocookie {
            session_sticky_hide_cookie upstream=insert_nocookie;
            proxy_pass http://insert_nocookie/;
        }

        location /test_insert_nocookie_notfound {
            session_sticky_hide_cookie upstream=insert_nocookie;
            proxy_pass http://insert_nocookie;
        }

        location /test_rewrite_no_header {
            proxy_pass http://rewrite/;
        }

        location /test_cookie {
            session_sticky_hide_cookie upstream=nocookie;
            proxy_pass http://nocookie/;
        }

        location /test_havecookie {
            session_sticky_hide_cookie upstream=havecookie;
            proxy_pass http://havecookie/;
        }

        location /test_nothing {
            proxy_pass http://nothing/;
        }
    }
}

EOF


#####################################################################################
#####################################################################################
$t->run();
my $r = http_get('/test_insert_indirect');
#1
like($r, qr/200 OK/, 'test insert frist seen');
my $cookie = getcookie($r);
my $res = getres($r);
my $now = time();
my $sid = getsid($cookie);
#2
like(my_http_get('/test_insert_indirect', "$sid\|$now\|$now"), qr/$res/, 'insert with cookie');
$r = http_get('/test_insert');
$cookie = getcookie($r);
$res = getres($r);
$sid = getsid($cookie);
$now = $now - 1000;
if ($res eq 9000) {
    $res = 9001;
} else {
    $res = 9000;
}
#3
like(my_http_get('/test_insert', "$sid\|$now\|$now"), qr/$res/, 'insert with cookie, maxidle timeout');
$r = http_get('/test_insert_indirect');
#4
like($r, qr/test=\w{32}\|\d*\|\d*;/, 'insert with indirect');
#5
like($r, qr/\d{4}/, 'insert with indirect -- upstream don\'t recv cookie');
#6
$r = http_get('/test_rewrite');
$cookie = getcookie($r);
$res = getres($r);
like($r, qr/set-cookie:[^\w]*test=\w{32}/i, 'rewrite -- upstream set cookie');
unlike($r, qr/set-cookie:[^\w]*test=\w{32};[^\w]*domain/i, 'rewrite -- upstream set cookie and session_sticky modify the value only');
like(my_http_get('/test_rewrite', "$cookie"), qr/$res/, 'rewrite -- with cookie in request');

#7
unlike(http_get('/test_rewrite_no_setcookie'), qr/set-cookie:[^\w]*test=/i, 'rewrite -- upstream don\'t set cookie');
#8
$r = http_get('/test_prefix');
like($r, qr/set-cookie:[^\w]*test=\w{32}\~\w*/i, 'prefix -- upstream set cookie');
$cookie = getcookie($r);
$res = getres($r);
like(my_http_get('/test_prefix', $cookie), qr/$res/, 'prefix -- with cookie in request');
#9
unlike(http_get('/test_prefix_no_setcookie'), qr/set-cookie:[^\w]*test=\w{32}\W*\w*/i, 'prefix -- upstream don\'t set cookie');

#10
$now = time();
like(my_http_get('/test_insert_indirect_off', "asdfasfasdfsadf\|$now\|$now"), qr/502/, 'insert with indirect and fallback off');
#11
like(http_get('/test_insert_indirect_off'), qr/200/, 'insert with indirct --- frist and fallback off');
#12
$now = time();
like(my_http_get('/test_insert_off', "asdfasfasdfsadf\|$now\|$now"), qr/502/, 'insert without indirect adn fallback off');
#13
like(http_get('/test_insert_off'), qr/200/, 'insert -- frist and fallback off');
#14
$now = time();
like(my_http_get('/test_rewrite_off', "asdfasfasdfsadf\|$now\|$now"), qr/502/, 'rewrite -- fallback off');
#15
like(http_get('/test_rewrite_off'), qr/200/, 'rewrite -- frist and fallback off');
#16
$now = time();
like(my_http_get('/test_prefix_off', "asdfasfasdfsadf~\|$now\|$now"), qr/502/, 'prefix-cookie invailied');
#17
like(http_get('/test_prefix_off'), qr/200/, 'prefix -- frist and fallback off');
#18
unlike(http_get('/test_insert_nodomain'), qr/domain/i, 'insert -- without domain');
#19
like(http_get('/test_insert_nopath'), qr/path=\//i, 'insert -- without path');
#20
unlike(http_get('/test_insert_nomaxage'), qr/max-age/i, 'insert--without max-age');
#21
$r = http_get('/test_insert_nomaxidle');
like($r, qr/set-cookie:[^\w]*test=\w*/i, 'insert--without maxidle');
#22
unlike($r, qr/set-cookie:\W*test=\w{32}\|\d*\|\d*/i, 'insert--without maxidle');
#23
like(http_get('/test_insert_nocookie'), qr/route/i, 'insert--without cookie');
#24
like(http_get('/test_insert_nocookie_notfound'), qr/404 Not Found/, 'Not Found');
#25
$r = http_get('/test_rewrite_no_header');
$cookie = getcookie($r);
$res = getres($r);
like(my_http_get('/test_rewrite_no_header', $cookie), qr/$res/, 'not config session_sticky_hide_cookie');
$r = http_get('/test_insert_nomalife');
$cookie=getcookie($r);
$res=getres($r);
like($r, qr/set-cookie: test=\w{32}/i, 'no maxlife');
like(my_http_get('/test_insert_nomalife', $cookie), qr/$res/, 'nomaxlif with cookie');
$r = http_get('/test_cookie');
$cookie = getcookie($r);
like($r, qr/200/, 'indirect--no cookie in request and no cookie to upstream');
like(my_http_get('/test_cookie', $cookie), qr/200/, 'indirect--with cookie in request and cookie to upstream');
$r = http_get('/test_havecookie');
$cookie = getcookie($r);
like($r, qr/200/, 'direct--no cookie in request and no cookie to upstream');
like(my_http_get('/test_havecookie', $cookie), qr/401/, 'direct--with cookie in request and cookie to upstream');
$r = http_get('/test_nothing');
$cookie = getcookie($r);
$res = getres($r);
like($r, qr/200/, 'prefix--without maxidle or maxlife');
like(my_http_get('/test_nothing', $cookie), qr/$res/, 'prefix--without maxidle or maxlife');
$r = http_get('/test_hash');
like($r, qr/set-cookie: test=\d{4}/i, "hash=plain");
$cookie = getcookie($r);
$res = getres($r);
$r = my_http_get('/test_hash', $cookie);
like($r, qr/$res/, 'hash=plain, the same real server');
$t->stop();
#####################################################################################
#####################################################################################


sub getcookie
{
    my ($c) = @_;
    $c =~ m/Set-cookie: test=([^;\r\n]*)/i;
    return $1;
}

sub getsid
{
    my ($c) = @_;
    $c =~ m/([^|]*)/;
    return $1;
}

sub getlastseen
{
    my ($c) = @_;
    $c =~ m/\|(\d*)\|/;
    return $1;
}

sub getfristseen
{
    my ($c) = @_;
    $c =~ m/\|(\d*)$/;
    return $1;
}

sub getres
{
    my ($c) = @_;
    $c =~ m/\r\n\r\n(\d{4})/;
    return $1;
}

sub my_http_get
{
    my ($url, $cookie) = @_;
    my $r = http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Cookie: test=$cookie

EOF
}
