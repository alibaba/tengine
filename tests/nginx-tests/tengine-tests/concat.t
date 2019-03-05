#!/usr/bin/perl
# Concat_configuration_Unit_Test
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

my $t = Test::Nginx->new()->has(qw/http concat/)->plan(169);

$t->set_dso("ngx_http_concat_module", "ngx_http_concat_module.so");
$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

my $d = $t->testdir();

mkdir("$d/concatFile");
$t->write_file('concatFile/index.html', 'index');
$t->write_file('concatFile/tindex.html', 'tIndex');
$t->write_file('concatFile/hello.x', 'hello.x');
$t->write_file('concatFile/world.x', 'world.x');
$t->write_file('concatFile/hello.js', 'hello.js');
$t->write_file('concatFile/world.js', 'world.js');
$t->write_file('concatFile/jack.js', 'jack.js');
$t->write_file('concatFile/hello.css', 'hello.css');
$t->write_file('concatFile/world.css', 'world.css');
$t->write_file('concatFile/jack.css', 'jack.css');
$t->write_file('concatFile/hello.html', 'hello.html');
$t->write_file('concatFile/world.html', 'world.html');
$t->write_file('concatFile/jack.html', 'jack.html');
$t->write_file('concatFile/world.htm', 'world.htm');
$t->write_file('concatFile/jack.shtml', 'jack.shtml');
$t->write_file('concatFile/hello.jpeg', 'hello.jpeg');
$t->write_file('concatFile/world.jpeg', 'world.jpeg');
$t->write_file('concatFile/jack.jpeg', 'jack.jpeg');
$t->write_file('concatFile/hello', 'hello');
$t->write_file('concatFile/world', 'world');
$t->write_file('concatFile/jack', 'jack');
$t->write_file('concatFile/t1.js', '1');
$t->write_file('concatFile/t2.js', '2');
$t->write_file('concatFile/t3.js', '3');
$t->write_file('concatFile/t4.js', '4');
$t->write_file('concatFile/t5.js', '5');
$t->write_file('concatFile/t6.js', '6');
$t->write_file('concatFile/t7.js', '7');
$t->write_file('concatFile/t8.js', '8');
$t->write_file('concatFile/t9.js', '9');
$t->write_file('concatFile/t10.js', '10');
$t->write_file('concatFile/t11.js', '11');
$t->write_file('concatFile/t12.js', '12');
$t->write_file('concatFile/t13.js', '13');
$t->write_file('concatFile/t14.js', '14');
$t->write_file('concatFile/t15.js', '15');

###############################################################################
#Test1
#concat on test
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message1 = qr/hello.jsworld.js/s;

like(http_get('/concatFile/??hello.js,world.js'), $concat_message1, 'concat - concat on test');

$t->stop();
###############################################################################
###############################################################################
#Test2
#concat off test
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message2 = qr/index/s;

like(http_get('/concatFile/??hello.js,world.js'), $concat_message2, 'concat - concat off test');

$t->stop();
###############################################################################
###############################################################################
#Test3
#concat off and concat files 0 test
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message3 = qr/index/s;

like(http_get('/concatFile/'), $concat_message3, 'concat - concat off and concat files 0 test');

$t->stop();
###############################################################################
###############################################################################
#Test4
#concat on and concat files 0 test
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message4 = qr/index/s;

like(http_get('/concatFile/'), $concat_message4, 'concat - concat on and concat files 0 test');

$t->stop();
###############################################################################
###############################################################################
#Test5
#concat_unique on test -- not the same type
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message5 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.css,jack.js'), $concat_message5, 'concat - concat_unique on test -- not the same type');

$t->stop();
###############################################################################
###############################################################################
#Test6
#concat_unique on test -- the same type
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message6 = qr/hello.jsworld.jsjack.js/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js'), $concat_message6, 'concat - concat_unique on test -- the same type');

$t->stop();
###############################################################################
###############################################################################
#Test7
#concat_unique off test -- not the same type
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message7 = qr/hello.jsworld.cssjack.js/s;

like(http_get('/concatFile/??hello.js,world.css,jack.js'), $concat_message7, 'concat - concat_unique on test -- not the same type');

$t->stop();
###############################################################################
###############################################################################
#Test8
#concat_unique off test -- the same type
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message8 = qr/hello.jsworld.jsjack.js/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js'), $concat_message8, 'concat - concat_unique on test -- the same type');

$t->stop();
###############################################################################
###############################################################################
#Test9
#concat_max_files 10 test -- 1 file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message9 = qr/hello.js/s;

like(http_get('/concatFile/??hello.js'), $concat_message9, 'concat - concat_max_files 10 test -- 1 file');

$t->stop();
###############################################################################
###############################################################################
#Test10
#concat_max_files 10 test -- 5 file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message10 = qr/hello.jsworld.jsjack.js12/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js'), $concat_message10, 'concat - concat_max_files 10 test -- 5 file');

$t->stop();
###############################################################################
###############################################################################
#Test11
#concat_max_files 10 test -- 10 file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message11 = qr/hello.jsworld.jsjack.js1234567/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js,t3.js,t4.js,t5.js,t6.js,t7.js'), $concat_message11, 'concat - concat_max_files 10 test -- 10 file');

$t->stop();
###############################################################################
###############################################################################
#Test12
#concat_max_files 10 test -- 11 file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message12 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js,t3.js,t4.js,t5.js,t6.js,t7.js,t8.js'), $concat_message12, 'concat - concat_max_files 10 test -- 11 file');

$t->stop();
###############################################################################
###############################################################################
#Test13
#concat_max_files 10 test -- 0 file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message13 = qr/index/s;

like(http_get('/concatFile/??'), $concat_message13, 'concat - concat_max_files 10 test -- 0 file');

$t->stop();
###############################################################################
###############################################################################
#Test14
#concat_types text/css, text/html test -- concat_unique on(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message14 = qr/hello.htmlworld.htmljack.html/s;

like(http_get('/concatFile/??hello.html,world.html,jack.html'), $concat_message14, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique on(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test15
#concat_types application/javascript  , text/css, text/html test -- concat_unique on(not fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message15 = qr/400/s;

like(http_get('/concatFile/??hello.jpeg,world.jpeg,jack.jpeg'), $concat_message15, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique on(not fix)');

$t->stop();
###############################################################################
###############################################################################
#Test16
#concat_types application/javascript  , text/css, text/html test -- concat_unique on(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message16 = qr/hello.htmlworld.htmjack.shtml/s;

like(http_get('/concatFile/??hello.html,world.htm,jack.shtml'), $concat_message16, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique on(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test17
#concat_types text/css, text/html test -- concat_unique on(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message17 = qr/hello.cssworld.cssjack.css/s;

like(http_get('/concatFile/??hello.css,world.css,jack.css'), $concat_message17, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique on(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test18
#concat_types text/css, text/html test -- concat_unique on(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message18 = qr/hello.jsworld.jsjack.js/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js'), $concat_message18, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique on(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test19
#concat_types text/css, text/html test -- concat_unique off(not fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message19 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.html,jack.css,hello.jpeg'), $concat_message19, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique off(not fix)');

$t->stop();
###############################################################################
###############################################################################
#Test20
#concat_types application/javascript  , text/css, text/html test -- concat_unique off(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message20 = qr/hello.htmlworld.htmljack.html/s;

like(http_get('/concatFile/??hello.html,world.html,jack.html'), $concat_message20, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique off(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test21
#concat_types text/css, text/html test -- concat_unique off(not fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message21 = qr/400/s;

like(http_get('/concatFile/??hello.jpeg,world.jpeg,jack.jpeg'), $concat_message21, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique off(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test22
#concat_types text/css, text/html test -- concat_unique off(not fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message22 = qr/400/s;

like(http_get('/concatFile/??hello,world,jack'), $concat_message22, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique off(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test23
#concat_types text/css, text/html test -- concat_unique off(fix)
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique off;
            concat_types text/css text/html;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message23 = qr/hello.jsworld.htmljack.css/s;

like(http_get('/concatFile/??hello.js,world.html,jack.css'), $concat_message23, 'concat - concat_types application/javascript  , text/css, text/html test -- concat_unique off(fix)');

$t->stop();
###############################################################################
###############################################################################
#Test24
#concat on normal request index.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message24 = qr/index/s;

like(http_get('/concatFile/index.html'), $concat_message24, 'concat - concat on normal request index.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test25
#concat on normal request tindex.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message25 = qr/tIndex/s;

like(http_get('/concatFile/tindex.html'), $concat_message25, 'concat - concat on normal request tindex.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test26
#concat off normal request index.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message26 = qr/index/s;

like(http_get('/concatFile/index.html'), $concat_message26, 'concat - concat off normal request index.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test27
#concat off normal request tindex.html not combin
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

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message27 = qr/tIndex/s;

like(http_get('/concatFile/tindex.html'), $concat_message27, 'concat - concat off normal request tindex.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test28
#concat_unique on normal request index.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message28 = qr/index/s;

like(http_get('/concatFile/index.html'), $concat_message28, 'concat - concat_unique on normal request index.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test29
#concat_unique on normal request tindex.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique on;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message29 = qr/tIndex/s;

like(http_get('/concatFile/tindex.html'), $concat_message29, 'concat - concat_unique on normal request tindex.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test30
#concat_unique off normal request index.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message30 = qr/index/s;

like(http_get('/concatFile/index.html'), $concat_message30, 'concat - concat_unique off normal request index.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test31
#concat_unique off normal request tindex.html not combin
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_unique off;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message31 = qr/tIndex/s;

like(http_get('/concatFile/tindex.html'), $concat_message31, 'concat - concat_unique off normal request tindex.html not combin');

$t->stop();
###############################################################################
###############################################################################
#Test32
#concat_max_files: 1 out of the scale
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 1;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message32 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.js'), $concat_message32, 'concat - concat_max_files: 1 out of the scale');

$t->stop();
###############################################################################
###############################################################################
#Test33
#concat_max_files: 1 in the scale
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 1;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message33 = qr/hello.js/s;

like(http_get('/concatFile/??hello.js'), $concat_message33, 'concat - concat_max_files: 1 in the scale');

$t->stop();
###############################################################################
###############################################################################
#Test34
#concat_max_files: 17 ; one file
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 17;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message34 = qr/hello.js/s;

like(http_get('/concatFile/??hello.js'), $concat_message34, 'concat - concat_max_files: 17 ; one file');

$t->stop();
###############################################################################
###############################################################################
#Test35
#concat_max_files: 17 ; 9 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 17;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message35 = qr/hello.jsworld.jsjack.js123456/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js,t3.js,t4.js,t5.js,t6.js'), $concat_message35, 'concat - concat_max_files: 17 ; 9 files');

$t->stop();
###############################################################################
###############################################################################
#Test36
#concat_max_files: 17 ; 17 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 17;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message36 = qr/hello.jsworld.jsjack.js1234567891011121314/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js,t3.js,t4.js,t5.js,t6.js,t7.js,t8.js,t9.js,t10.js,t11.js,t12.js,t13.js,t14.js'), $concat_message36, 'concat - concat_max_files: 17 ; 17 files');

$t->stop();
###############################################################################
###############################################################################
#Test37
#concat_max_files: 17 ; 18 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 17;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message37 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.js,jack.js,t1.js,t2.js,t3.js,t4.js,t5.js,t6.js,t7.js,t8.js,t9.js,t10.js,t11.js,t12.js,t13.js,t14.js,t15.js'), $concat_message37, 'concat - concat_max_files: 17 ; 18 files');

$t->stop();
###############################################################################
###############################################################################
#Test38
#concat_max_files: 17 ; 0 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 17;
        }
    }
}

EOF

$t->run();
###############################################################################
my $concat_message38 = qr/index/s;

like(http_get('/concatFile/??'), $concat_message38, 'concat - concat_max_files: 17 ; 0 files');

$t->stop();
###############################################################################
###############################################################################
#Test39
#concat_max_files: 100 ; 100 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 1000;
        }
    }
}

EOF

$t->run();
###############################################################################
my $i;
my $url="/concatFile/??";
foreach $i(1..100){
	$url=$url."hello.js,";
}
my $tmp;
foreach $i(1..100){
	$tmp=$tmp."hello.js"
}


my $concat_message39 = qr/$tmp/s;

like(http_get($url), $concat_message39, 'concat - concat_max_files: 100 ; 100 files');

$t->stop();
###############################################################################
###############################################################################
#Test40
#concat_max_files: 100 ; 101 files
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_max_files 1000;
        }
    }
}

EOF

$t->run();
###############################################################################
my $i2;
my $url2="/concatFile/??";
foreach $i2(1..101){
	$url2=$url2."hello.js,";
}
my $tmp2;
foreach $i2(1..101){
	$tmp2=$tmp2."hello.js"
}


my $concat_message40 = qr/$tmp2/s;

like(http_get($url2), $concat_message40, 'concat - concat_max_files: 100 ; 101 files');

$t->stop();
###############################################################################
###############################################################################
#Test41
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################

my $concat_message41 = qr/400/s;

like(http_get('/concatFile/??hello.x,world.x'), $concat_message41, 'concat - concat_types not inside the mime.types');

$t->stop();
###############################################################################
###############################################################################
#Test42
#concat_unique as default test; same type input 
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################

my $concat_message42 = qr/hello.jsworld.js/s;

like(http_get('/concatFile/??hello.js,world.js'), $concat_message42, 'concat - concat_unique as default test; same type input ');

$t->stop();
###############################################################################
###############################################################################
#Test43
#concat_unique as default test; not the same type input 
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################

my $concat_message43 = qr/400/s;

like(http_get('/concatFile/??hello.js,world.css'), $concat_message43, 'concat - concat_unique as default test; not the same type input ');

$t->stop();
###############################################################################
###############################################################################
#Test44
#concat_unique as default test; not the same type input 
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################

my $concat_message44 = qr/hello.cssworld.css/s;

like(http_get('/concatFile/??hello.css,world.css'), $concat_message44, 'concat - concat_unique as default test; same type input ');

$t->stop();
############################################################################
############################################################################
#Test45
#concat_delimiter "\n"
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process  off;
daemon          off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_delimiter "\n";
        }
    }
}

EOF

$t->run();
###########################################################################

my $concat_message45 = qr/hello.css\nworld.css/s;
like(http_get('/concatFile/??hello.css,world.css'), $concat_message45, 'concat - insert separator');

$t->stop();
############################################################################
############################################################################
#Test46
#concat_delimiter "\n"
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process  off;
daemon          off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_delimiter "\n";
            concat_ignore_file_error off;
        }
    }
}

EOF

$t->run();
###########################################################################

my $concat_message46 = qr/404/s;
like(http_get('/concatFile/??notfound.css,hello.css,world.css'), $concat_message46, 'concat - insert separator');

$t->stop();
############################################################################
############################################################################
#Test47
#concat_delimiter "\n"
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process  off;
daemon          off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
            concat_delimiter "\n";
            concat_ignore_file_error on;
        }
    }
}

EOF

$t->run();
###########################################################################

my $concat_message47 = qr/hello.css\nworld.css/s;
like(http_get('/concatFile/??notfound.css,hello.css,world.css'), $concat_message47, 'concat - insert separator');

$t->stop();

#############################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }

    default_type application/octet-stream;

    server {
        listen  127.0.0.1:8080;
        server_name localhost;

        location / {
            concat  on;
            default_type application/octet-stream;
            concat_delimiter "\n";

            gzip on;
        }

        location /nodelimiter/ {
            concat  on;
        }

        location /unique/ {
            concat on;
            concat_unique on;
            concat_delimiter "\n";
        }
    }
}

EOF

$t->write_file('t1.js', '1');
$t->write_file('t2.js', '2');
$t->write_file('t3.js', '3');

$d = $t->testdir();

mkdir("$d/nodelimiter");
$t->write_file('nodelimiter/a.js', 'a');
$t->write_file('nodelimiter/b.js', 'b');
$t->write_file('nodelimiter/c.js', 'c');

mkdir("$d/unique");
$t->write_file('unique/1.css', '1');
$t->write_file('unique/2.css', '2');
$t->write_file('unique/1.js', '1');
$t->write_file('unique/2.js', '2');

$t->run();
###############################################################

my $r;

like(http_get('/??t1.js,t2.js,t3.js'), qr/1\n2\n3/, 'has separator');
like(http_get('/nodelimiter/??a.js,b.js,c.js'), qr/abc/, 'doesn\'t have separator');
like(http_get('/unique/??1.css,2.css'), qr/1\n2/, 'unique with separator - the same type');
like(http_get('/unique/??1.css,1.js'), qr/400/, 'unique with separator - different types');
$t->stop();
# Concat_result_Unit_Test
###############################################################################


$d = $t->testdir();

mkdir("$d/concatFile");
$t->write_file('concatFile/hello.js', 'hello.js');
$t->write_file('concatFile/world.js', 'world.js');
$t->write_file('concatFile/jack.js', 'jack.js');

$t->write_file('concatFile/empty.js', '');
$t->write_file('concatFile/chinese.js', 'ÄãºÃÂð£¿');

my $largeFile="a";

foreach $i(1..102400){
	$largeFile = $largeFile."a";
}

$t->write_file('concatFile/LargeFile.js', $largeFile);

###############################################################################
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
$concat_message1 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js,empty.js'), $concat_message1, 'concat - concat result test -- empty file');

$concat_message2 = qr/404 Not Found/s;
like(http_get('/concatFile/??hello.js,helloworld.js,world.js'), $concat_message2, 'concat - concat result test -- no eixt file middle');

$concat_message3 = qr/404 Not Found/s;
like(http_get('/concatFile/??helloworld.js,hello.js,world.js'), $concat_message3, 'concat - concat result test -- no eixt file front');

$concat_message4 = qr/404 Not Found/s;
like(http_get('/concatFile/??hello.js,world.js,helloworld.js'), $concat_message4, 'concat - concat result test -- no eixt file back');

$concat_message5 = qr/hello.jsworld.jsÄãºÃÂð£¿/s;
like(http_get('/concatFile/??hello.js,world.js,chinese.js'), $concat_message5, 'concat - concat result test -- include Chinese words');

$tmp = "hello.jsworld.js".$largeFile;
$concat_message6 = qr/$tmp/s;
like(http_get('/concatFile/??hello.js,world.js,LargeFile.js'), $concat_message6, 'concat - concat result test -- include 100k file');


$t->stop();
###############################################################################


$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
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

$d = $t->testdir();

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

$t->run();

###############################################################################

like(http_get('/?'), qr/403/, 'one question mark');
like(http_get('/??'), qr/403/, 'two question marks');
like(http_get('/???'), qr/400/, 'three question marks');
like(http_get('/????'), qr/400/, 'four question marks');
like(http_get('/??t1.html'), qr/one/, 'concat - one file');
like(http_get('/??t1.html,'), qr/one/, 'concat - one more comma');
like(http_get('/??t1.html,,'), qr/one/, 'concat - two more commas');
like(http_get('/??t1.html,,,'), qr/one/, 'concat - thre more commas');
like(http_get('/??t1.html,,t2.html'), qr/onetwo/, 'concat - with one more comma');
like(http_get('/??t1.html,,,t2.html'), qr/onetwo/, 'concat - with two more commas');

$r = http_get('/??t1.html,t2.html');
like($r, qr/onetwo/, 'concat - two files');
like($r, qr/^Content-Type: text\/html/m, 'concat - content type');

$r = http_get('/??t1.html,ta.htm,tb.shtml');
like($r, qr/onetatb/, 'concat - 3 different suffixes');
like($r, qr/^Content-Type: text\/html/m, 'concat - html type');

$r = http_get('/??a.js,b.js');
like($r, qr/javascriptajavascriptb/, 'concat - two javascript files');
like($r, qr/^Content-Type: application\/javascript/m, 'concat - content type (javascript)');

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
like($r, qr/^Content-Type: application\/javascript/m, 'concat - content type (default js)');

$r = http_get('/cssjs/??1.html,2.html');
like($r, qr/400/, 'concat - html files (default not support)');

$r = http_get('/cssjs/??1.js,1.css');
like($r, qr/400/, 'concat - mixed content types');

like(http_get('/??t1.html,t2.html,t100.html'), qr/404 Not Found/, 'concat - has not found file');
like(http_get('/??t1.html,'), qr/one/, 'concat - one file and ","');
like(http_get('/??t1.html,t2.html,'), qr/onetwo/, 'concat - two files and ","');
like(http_get('/??t1.html?t=20100524'), qr/one/, 'concat - timestamp');
like(http_get('/??t1.html,t2.html?t=20100524'), qr/onetwo/, 'concat - timestamp 2');
like(http_get('/??t1.html?t=1234,t2.html?tt=234234'), qr/onetwo/, 'concat - timestamp 3');
like(http_get('/??t1.html?t=1234,t2.html'), qr/onetwo/, 'concat - timestamp 4');
like(http_get('/??t1.html,t2.html?t=123'), qr/onetwo/, 'concat - timestamp 5');
like(http_get('/??t1.html,t2.html?t=123'), qr/onetwo/, 'concat -timestamp 6');
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
$t->stop();
##############################################################################

$d = $t->testdir();

mkdir("$d/concatFile");
$t->write_file('concatFile/hello.js', 'hello.js');
$t->write_file('concatFile/world.js', 'world.js');
$t->write_file('concatFile/jack.js', 'jack.js');

mkdir("$d/concatFile/dir1");
$t->write_file('concatFile/dir1/hello.js', 'hello.js_dir1');
$t->write_file('concatFile/dir1/world.js', 'world.js_dir1');
$t->write_file('concatFile/dir1/jack.js', 'jack.js_dir1');

###############################################################################
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html                             html htm shtml;
        text/css                              css;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
    }
    
    default_type application/octet-stream;

    server {
        listen      127.0.0.1:8080;
        server_name localhost;

        location /concatFile/ {
            concat  on;
        }
    }
}

EOF

$t->run();
###############################################################################
$concat_message1 = qr/404/s;
like(http_get('/concatFile/hello.js,world.js'), $concat_message1, 'concat - concat_url test -- no question mark');

$concat_message2 = qr/200/s;
like(http_get('/concatFile/?hello.js,world.js'), $concat_message2, 'concat - concat_url test -- one question mark front');

$concat_message3 = qr/hello.js/s;
like(http_get('/concatFile/hello.js?world.js'), $concat_message3, 'concat - concat_url test -- one question mark middle');

$concat_message4 = qr/404/s;
like(http_get('/concatFile/hello.js,world.js?'), $concat_message4, 'concat - concat_url test -- one question mark back');

$concat_message5 = qr/hello.js/s;
like(http_get('/concatFile/hello.js??world.js'), $concat_message5, 'concat - concat_url test -- two question mark middle');

$concat_message6 = qr/404/s;
like(http_get('/concatFile/hello.js,world.js??'), $concat_message6, 'concat - concat_url test -- two question mark back');

$concat_message7 = qr/200/s;
like(http_get('/concatFile/hello.js?world.js?'), $concat_message7, 'concat - concat_url test -- two question mark seprate');

$concat_message8 = qr/200/s;
like(http_get('/concatFile/?hello.js?world.js'), $concat_message8, 'concat - concat_url test -- two question mark seprate');

$concat_message9 = qr/200/s;
like(http_get('/concatFile/?hello.js,world.js?'), $concat_message9, 'concat - concat_url test -- two question mark seprate');

$concat_message10 = qr/world.js/s;
like(http_get('/concatFile/???hello.js,world.js'), $concat_message10, 'concat - concat_url test -- three question mark front');

$concat_message11 = qr/404/s;
like(http_get('/concatFile/hello.js,world.js???'), $concat_message11, 'concat - concat_url test -- three question mark back');

$concat_message12 = qr/hello.js/s;
like(http_get('/concatFile/hello.js???world.js'), $concat_message12, 'concat - concat_url test -- three question mark middle');

$concat_message13 = qr/200/s;
like(http_get('/concatFile/?hello.js??world.js'), $concat_message13, 'concat - concat_url test -- three question mark seprate middle');

$concat_message14 = qr/200/s;
like(http_get('/concatFile/?hello.js?world.js?'), $concat_message14, 'concat - concat_url test -- three question mark seprate');

$concat_message15 = qr/hello.js/s;
like(http_get('/concatFile/??hello.js?world.js'), $concat_message15, 'concat - concat_url test -- three question mark seprate');

$concat_message16 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js?'), $concat_message16, 'concat - concat_url test -- three question mark seprate');

$concat_message17 = qr/hello.js/s;
like(http_get('/concatFile/hello.js??world.js?'), $concat_message17, 'concat - concat_url test -- three question mark seprate');

$concat_message18 = qr/200/s;
like(http_get('/concatFile/?hello.js,world.js??'), $concat_message18, 'concat - concat_url test -- three question mark seprate');

$concat_message19 = qr/hello.js/s;
like(http_get('/concatFile/hello.js?world.js??'), $concat_message19, 'concat - concat_url test -- three question mark seprate');

$concat_message20 = qr/hello.js/s;
like(http_get('/concatFile/??hello.js??world.js'), $concat_message20, 'concat - concat_url test -- four question mark');

$concat_message21 = qr/hello.js/s;
like(http_get('/concatFile/hello.js??world.js??'), $concat_message21, 'concat - concat_url test -- four question mark');

$concat_message22 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js??'), $concat_message22, 'concat - concat_url test -- four question mark');

$concat_message23 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??,hello.js,world.js'), $concat_message23, 'concat - concat_url test -- one more comma front');

$concat_message24 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??,,hello.js,world.js'), $concat_message24, 'concat - concat_url test -- two more commas front');

$concat_message25 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js,'), $concat_message25, 'concat - concat_url test -- one more comma back');

$concat_message26 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js,,'), $concat_message26, 'concat - concat_url test -- two more commas back');

$concat_message27 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,world.js,,,'), $concat_message27, 'concat - concat_url test -- three more commas back');

$concat_message28 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,,world.js'), $concat_message28, 'concat - concat_url test -- one more comma middle');

$concat_message29 = qr/hello.jsworld.js/s;
like(http_get('/concatFile/??hello.js,,,world.js'), $concat_message29, 'concat - concat_url test -- two more commas middle');

$concat_message30 = qr/hello.jsworld.js_dir1jack.js/s;
like(http_get('/concatFile/??hello.js,dir1/world.js,jack.js'), $concat_message30, 'concat - concat_url test -- with one directory middle');

$concat_message31 = qr/hello.js_dir1world.jsjack.js/s;
like(http_get('/concatFile/??dir1/hello.js,world.js,jack.js'), $concat_message31, 'concat - concat_url test -- with one directory front');

$concat_message32 = qr/hello.jsworld.jsjack.js_dir1/s;
like(http_get('/concatFile/??hello.js,world.js,dir1/jack.js'), $concat_message32, 'concat - concat_url test -- with one directory back');

$concat_message33 = qr/hello.js_dir1world.js_dir1jack.js/s;
like(http_get('/concatFile/??dir1/hello.js,dir1/world.js,jack.js'), $concat_message33, 'concat - concat_url test -- with two directory AAB');

$concat_message34 = qr/hello.js_dir1world.jsjack.js_dir1/s;
like(http_get('/concatFile/??dir1/hello.js,world.js,dir1/jack.js'), $concat_message34, 'concat - concat_url test -- with two directory ABA');

$concat_message35 = qr/hello.jsworld.js_dir1jack.js_dir1/s;
like(http_get('/concatFile/??hello.js,dir1/world.js,dir1/jack.js'), $concat_message35, 'concat - concat_url test -- with two directory BAA');

$concat_message36 = qr/hello.jsworld.js_dir1jack.js/s;
like(http_get('/concatFile/??hello.js,/dir1/world.js,jack.js'), $concat_message36, 'concat - concat_url test -- with one directory strarts with slash middle');

$concat_message37 = qr/hello.js_dir1world.jsjack.js/s;
like(http_get('/concatFile/??/dir1/hello.js,world.js,jack.js'), $concat_message37, 'concat - concat_url test -- with one directory strarts with slash front');

$concat_message38 = qr/hello.jsworld.jsjack.js_dir1/s;
like(http_get('/concatFile/??hello.js,world.js,/dir1/jack.js'), $concat_message38, 'concat - concat_url test -- with one directory strarts with slash back');

$concat_message39 = qr/hello.js_dir1world.js_dir1jack.js/s;
like(http_get('/concatFile/??/dir1/hello.js,/dir1/world.js,jack.js'), $concat_message39, 'concat - concat_url test -- with two directory strarts with slash AAB');

$concat_message40 = qr/hello.js_dir1world.jsjack.js_dir1/s;
like(http_get('/concatFile/??/dir1/hello.js,world.js,/dir1/jack.js'), $concat_message40, 'concat - concat_url test -- with two directory strarts with slash ABA');

$concat_message41 = qr/hello.jsworld.js_dir1jack.js_dir1/s;
like(http_get('/concatFile/??hello.js,/dir1/world.js,/dir1/jack.js'), $concat_message41, 'concat - concat_url test -- with two directory strarts with slash BAA');

$concat_message42 = qr/hello.js_dir1world.js_dir1jack.js/s;
like(http_get('/concatFile/??/dir1/hello.js,dir1/world.js,jack.js'), $concat_message42, 'concat - concat_url test -- with two directory and one of it strarts with slash ABC');

$concat_message43 = qr/hello.js_dir1world.jsjack.js_dir1/s;
like(http_get('/concatFile/??/dir1/hello.js,world.js,dir1/jack.js'), $concat_message43, 'concat - concat_url test -- with two directory and one of it strarts with slash ACB');

$concat_message44 = qr/hello.jsworld.js_dir1jack.js_dir1/s;
like(http_get('/concatFile/??hello.js,dir1/world.js,/dir1/jack.js'), $concat_message44, 'concat - concat_url test -- with two directory and one of it strarts with slash CBA');

$concat_message45 = qr/400/s;
like(http_get('/concatFile/??hello.js,../world.js,jack.js'), $concat_message45, 'concat - concat_url test -- bad request(../)');

$concat_message46 = qr/hello.jsworld.jsjack.js/s;
like(http_get('/concatFile/??hello.js,./world.js,jack.js'), $concat_message46, 'concat - concat_url test -- dot slash(./)');

$concat_message47 = qr/400/s;
like(http_get('/concatFile/??hello.js,./../world.js,jack.js'), $concat_message47, 'concat - concat_url test -- bad request(./../)');

my $concat_message48 = qr/400/s;
like(http_get('/concatFile/hello./??js,world.js,jack.js'), $concat_message48, 'concat - two question marks ./??js');

my $concat_message49 = qr/400/s;
like(http_get('/concatFile//??hello.js,world.js,jack.js,?'), $concat_message49, 'concat - in the end have a commas and question mark ,?');

my $concat_message50 = qr/404 Not Found/s;
like(http_get('/concatFile/??hello.js,world.js,jack.js,/'), $concat_message50, 'concat - in the end have a commas and / ,/');



$t->stop();
###############################################################################
