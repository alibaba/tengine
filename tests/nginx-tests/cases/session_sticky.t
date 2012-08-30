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

my $t = Test::Nginx->new()->plan(24);
$t->write_file_expand('9000', '9000');
$t->write_file_expand('9001', '9001');
$t->write_file_expand('9002', '9002');
$t->write_file_expand('9003', '9003');

my $d = $t->testdir();
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
    use     epoll;
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

    upstream insert_nomaxidle {
        session_sticky cookie=test mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    upstream insert_nocookie {
        session_sticky mode=insert fallback=on;
        server          127.0.0.1:9000;
        server          127.0.0.1:9001;
    }

    server {
        listen     127.0.0.1:9000;
        location / {
            add_header  Set-Cookie test=fuck;
            index       9000;
        }
    }

    server {
        listen     127.0.0.1:9001;
        location / {
            add_header Set-Cookie test=fuck;
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
        listen      127.0.0.1:8080;
        server_name localhost;

        location /test_insert_indirect {
            proxy_pass  http://insert_indirect/;
        }

        location /test_insert {
            proxy_pass  http://insert/;
        }

        location /test_rewrite {
            proxy_pass  http://rewrite/;
        }

        location /test_rewrite_no_setcookie {
            proxy_pass http://rewrite_no_setcookie/;
        }

        location /test_prefix {
            proxy_pass  http://prefix/;
        }

        location /test_prefix_no_setcookie {
            proxy_pass http://prefix_no_setcookie/;
        }

        location /test_insert_indirect_off {
            proxy_pass http://insert_indirect_off/;
        }

        location /test_insert_off {
            proxy_pass http://insert_off/;
        }
        location /test_rewrite_off {
            proxy_pass http://rewrite_off/;
        }

        location /test_prefix_off {
            proxy_pass http://prefix_off/;
        }

        location /test_insert_nodomain {
            proxy_pass http://insert_nodomain/;
        }

        location /test_insert_nopath {
            proxy_pass http://insert_nopath/;
        }

        location /test_insert_nomaxage {
            proxy_pass http://insert_nomaxage/;
        }

        location /test_insert_nomaxidle {
            proxy_pass http://insert_nomaxidle/;
        }

        location /test_insert_nocookie {
            proxy_pass http://insert_nocookie/;
        }

        location /test_insert_nocookie_notfound {
            proxy_pass http://insert_nocookie;
        }
    }
}

EOF


#####################################################################################
#####################################################################################
$t->run();
my $r = http_get('/test_insert');
#1
like($r, qr/200 OK/, 'test insert frist seen');
my $cookie = getcookie($r);
my $res = getres($r);
my $now = time();
my $sid = getsid($cookie);
#2
like(my_http_get('/test_insert', "$sid!$now^$now"), qr/$res/, 'insert with cookie');
$now = $now - 1000;
if ($res eq 9000) {
    $res = 9001;
} else {
    $res = 9000;
}
#3
like(my_http_get('/test_insert', "$sid!$now^$now"), qr/$res/, 'insert with cookie, maxidle timeout');
$r = http_get('/test_insert_indirect');
#4
like($r, qr/test=\w{32}!\d*\^\d*;/, 'insert with indirect');
#5
like($r, qr/\d{4}/, 'insert with indirect -- upstream don\'t recv cookie');
#6
like(http_get('/test_rewrite'), qr/set-cookie:[^\w]*test=\w{32};[^\w]*domain=/i, 'rewrite -- upstream set cookie');

#7
unlike(http_get('/test_rewrite_no_setcookie'), qr/set-cookie:[^\w]*test=/i, 'rewrite -- upstream don\'t set cookie');
#8
like(http_get('/test_prefix'), qr/set-cookie:[^\w]*test=\w{32}\~\w*/i, 'prefix -- upstream set cookie');
#9
unlike(http_get('/test_prefix_no_setcookie'), qr/set-cookie:[^\w]*test=\w{32}\W*\w*/i, 'prefix -- upstream don\'t set cookie');

#10
$now = time();
like(my_http_get('/test_insert_indirect_off', "asdfasfasdfsadf!$now^$now"), qr/502/, 'insert with indirect and fallback off');
#11
like(http_get('/test_insert_indirect_off'), qr/900\d/, 'insert with indirct --- frist and fallback off');
#12
$now = time();
like(my_http_get('/test_insert_off', "asdfasfasdfsadf!$now^$now"), qr/502/, 'insert without indirect adn fallback off');
#13
like(http_get('/test_insert_off'), qr/900\d/, 'insert -- frist and fallback off');
#14
$now = time();
like(my_http_get('/test_rewrite_off', "asdfasfasdfsadf!$now^$now"), qr/502/, 'rewrite -- fallback off');
#15
like(http_get('/test_rewrite_off'), qr/900\d/, 'rewrite -- frist and fallback off');
#16
$now = time();
like(my_http_get('/test_prefix_off', "asdfasfasdfsadf!$now^$now"), qr/502/, 'prefix -- fallback off');
#17
like(http_get('/test_prefix_off'), qr/900\d/, 'prefix -- frist and fallback off');
#18
unlike(http_get('/test_insert_nodomain'), qr/domain/i, 'insert -- without domain');
#19
unlike(http_get('/test_insert_nopath'), qr/path/i, 'insert -- without path');
#20
unlike(http_get('/test_insert_nomaxage'), qr/max-age/i, 'insert--without max-age');
#21
$r = http_get('/test_insert_nomaxidle');
like($r, qr/set-cookie:[^\w]*test=\w*/i, 'insert--without maxidle');
#22
unlike($r, qr/set-cookie:\W*test=\w{32}!\d*^\d*/i, 'insert--without maxidle');
#23
like(http_get('/test_insert_nocookie'), qr/route/i, 'insert--without cookie');
#24
like(http_get('/test_insert_nocookie_notfound'), qr/404 Not Found/, 'Not Found');
$t->stop();
#####################################################################################
#####################################################################################


sub getcookie
{
    my ($c) = @_;
    $c =~ m/Set-cookie: test=([^;]*)/i;
    return $1;
}

sub getsid
{
    my ($c) = @_;
    $c =~ m/([^!]*)/;
    return $1;
}

sub getlastseen
{
    my ($c) = @_;
    $c =~ m/!(\d*)/;
    return $1;
}

sub getfristseen
{
    my ($c) = @_;
    $c =~ m/\^(\d*)/;
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
