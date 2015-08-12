#!/usr/bin/perl

# (C) lizi

# Test for tbpass.

###############################################################################

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;


###############################################################################

sub http_get_host($;$;%) {
    my ($url, $host, %extra) = @_;
    return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: $host

EOF
}

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;


    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host;
        }

    }
}

EOF

$t->run();

###############################################################################

like(http_get_host("/", "www.taobao.com"), qr/HTTP\/1.1 302/, 'auto read /etc/resolv.conf');

$t->stop();
###############################################################################
###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv.conf;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host;
        }

    }
}

EOF

$t->write_file('resolv.conf', 'nameserver 223.5.5.5');

$t->run();

like(http_get_host("/", "www.taobao.com"), qr/HTTP\/1.1 302/, 'resolver_file to resolv.conf');

$t->stop();
###############################################################################
###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv2.conf;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host;
        }

    }
}

EOF

$t->write_file('resolv2.conf', '   nameserver     223.5.5.5   ');

$t->run();

like(http_get_host("/", "www.taobao.com"), qr/HTTP\/1.1 302/, 'resolver_file to resolv2.conf');

$t->stop();
###############################################################################
###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv3.conf;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host;
        }

    }
}

EOF

$t->write_file_expand('resolv3.conf', <<'EOF');
nameserver 223.5.5.5
nameserver 114.114.114.114
EOF

$t->run();

like(http_get_host("/", "www.taobao.com"), qr/HTTP\/1.1 302/, 'resolver_file to resolv3.conf');

$t->stop();
###############################################################################
###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv4.conf;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host;
        }

    }
}

EOF

$t->write_file_expand('resolv4.conf', <<'EOF');

  nameserver 223.5.5.5
  nameserver 223.6.6.6
  nameserver  114.114.114.114  

EOF

$t->run();

like(http_get_host("/", "www.taobao.com"), qr/HTTP\/1.1 302/, 'resolver_file to resolv4.conf');

$t->stop();
###############################################################################
