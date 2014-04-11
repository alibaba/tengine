#!/usr/bin/perl

###############################################################################

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Time::Parse;


###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(77);

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
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires 30s;
        expires_by_types 32s text/xml;
        expires_by_types 29s image/jpeg;


        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires_by_types 2s text/html;
            expires_by_types 25s application/x-javascript;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires 27s;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires_by_types 40s image/jpeg;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types off image/jpeg;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires off;
            expires_by_types 10 image/jpeg;
        }
    }
}

EOF

system("mkdir $t->{_testdir}/path1");
system("mkdir $t->{_testdir}/path2");
system("mkdir $t->{_testdir}/path3");
system("mkdir $t->{_testdir}/path4");
system("mkdir $t->{_testdir}/path5");
system("mkdir $t->{_testdir}/path6");

$t->write_file('path1/test.html', 'test for html');
$t->write_file('path1/test.xml', 'test for xml');
$t->write_file('path1/test.rss', 'test for rss');
$t->write_file('path1/test.js', 'test for js');
$t->write_file('path1/test.gif', 'test for gif');
$t->write_file('path1/test.jpg', 'test for jpg');
$t->write_file('path1/test.txt', 'test for txt');
$t->write_file('path1/test.txt2', 'test for txt2');

$t->write_file('path2/test.html', 'test for html');
$t->write_file('path2/test.jpg', 'test for jpg');

$t->write_file('path3/test.html', 'test for html');
$t->write_file('path3/test.jpg', 'test for jpg');

$t->write_file('path4/test.jpg', 'test for jpg');
$t->write_file('path4/test.html', 'test for html');

$t->write_file('path5/test.jpg', 'test for jpg');
$t->write_file('path5/test.html', 'test for html');

$t->write_file('path6/test.jpg', 'test for jpg');
$t->write_file('path6/test.html', 'test for html');

$t->run();

###############################################################################

ok(checkexpire(http_get("/path1/test.html"), 2), "test html");
ok(checkexpire(http_get("/path1/test.xml"), 23), "test xml");
ok(checkexpire(http_get("/path1/test.rss"), 23), "test rss");
ok(checkexpire(http_get("/path1/test.js"), 25), "test js");
ok(checkexpire(http_get("/path1/test.gif"), 28), "test gif");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "test jpg");

ok(checkexpire(http_get("/path2/test.html"), 27), "test html for path2");
ok(checkexpire(http_get("/path2/test.jpg"), 29), "test jpg");

ok(checkexpire(http_get("/path3/test.jpg"), 29), "test jpg");
ok(checkexpire(http_get("/path3/test.html"), 30), "test html");

ok(checkexpire(http_get("/path4/test.jpg"), 40), "test jpg");
ok(checkexpire(http_get("/path4/test.html"), 30), "test html");

unlike(http_get("/path5/test.jpg"), qr/Expires/, 'jpeg off');
ok(checkexpire(http_get("/path5/test.html"), 30), "test html");

unlike(http_get("/path6/test.jpg"), qr/Expires/, 'off');
unlike(http_get("/path6/test.html"), qr/Expires/, 'off');

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');
unlike(http_get("/path3/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires off;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');
unlike(http_get("/path3/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires 1s;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path3/test.html"), 1), "");
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
unlike(http_get("/path5/test.jpg"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");
ok(checkexpire(http_get("/path6/test.jpg"), 1), "");

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires off;
        expires_by_types 3s text/html;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');
unlike(http_get("/path3/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
ok(checkexpire(http_get("/path4/test.html"), 3), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
unlike(http_get("/path5/test.jpg"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");
unlike(http_get("/path6/test.jpg"), qr/Expires/, '');

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires 1s;
        expires_by_types 3s text/html;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    } }

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');

ok(checkexpire(http_get("/path3/test.jpg"), 1), "");
ok(checkexpire(http_get("/path3/test.html"), 3), "");
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
ok(checkexpire(http_get("/path4/test.html"), 3), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
unlike(http_get("/path5/test.jpg"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");
ok(checkexpire(http_get("/path6/test.jpg"), 1), "");

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires_by_types 3s text/html;

        location /path1 {
            root %%TESTDIR%%;
            expires_by_types 23s application/rss+xml text/xml;
            expires 28s;
        }

        location /path2 {
            root %%TESTDIR%%;
            expires off;
        }

        location /path3 {
            root %%TESTDIR%%;
        }

        location /path4 {
            root %%TESTDIR%%;
            expires 28s;
        }

        location /path5 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
            expires off;
        }

        location /path6 {
            root %%TESTDIR%%;
            expires_by_types 23s text/html;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.xml"), 23), "");
ok(checkexpire(http_get("/path1/test.jpg"), 28), "");
unlike(http_get("/path2/test.html"), qr/Expires/, '');
ok(checkexpire(http_get("/path3/test.html"), 3), "");
unlike(http_get("/path3/test.jpg"), qr/Expires/, '');
ok(checkexpire(http_get("/path4/test.jpg"), 28), "");
ok(checkexpire(http_get("/path4/test.html"), 3), "");
unlike(http_get("/path5/test.html"), qr/Expires/, '');
unlike(http_get("/path5/test.jpg"), qr/Expires/, '');
ok(checkexpire(http_get("/path6/test.html"), 23), "");
unlike(http_get("/path6/test.jpg"), qr/Expires/, '');

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    expires off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires_by_types 3s text/html;

        location /path1 {
            root %%TESTDIR%%;
        }
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.html"), 3), "http server location");

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        text                                  txt;
        text/                                 txt2;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/x-javascript              js;
        application/rss+xml                   rss;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        expires_by_types 8s image/*;

        location /path1 {
            root %%TESTDIR%%;
            expires 4s;
            expires_by_types 3s text/*;
            expires_by_types 5s text/html;
        }

        location /path2 {
            root %%TESTDIR%%;
        }
 
    }
}

EOF

$t->run();

ok(checkexpire(http_get("/path1/test.html"), 5), "");
ok(checkexpire(http_get("/path1/test.xml"), 3), "");
ok(checkexpire(http_get("/path1/test.txt2"), 3), "");
ok(checkexpire(http_get("/path1/test.txt"), 4), "");

ok(checkexpire(http_get("/path2/test.jpg"), 8), "");

$t->stop();

 
sub checkexpire
{
    my($c, $t) = @_;
    my $date = getHead($c, "Date");
    my $expires = getHead($c, "Expires");

    if ($expires eq "") {
        return 0;
    }

    $date = str2time($date);
    $expires = str2time($expires);

    $date += $t;

    if ($date eq $expires) {
        return 1;
    }
    return 0;
}

sub getHead
{
    my($c,$head) = @_;
    my @r = split(/\r\n\r\n/, $c);
    $c = $r[0];
    @r = split(/\r\n/, $c);

    foreach (@r) {
        my @sp = split(/$head:/, $_);
        my $num = @sp;
        if ($num eq 2) {
            return $sp[1];
        }
    }
}
