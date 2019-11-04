#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx realip module, 'unix:' and hostname in set_real_ip_from.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http realip proxy unix/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       unix:%%TESTDIR%%/unix.sock;
        server_name  localhost;

        location /1 {
            set_real_ip_from  localhost;
            add_header X-IP $remote_addr;
        }

        location /2 {
            set_real_ip_from  unix:;
            add_header X-IP $remote_addr;
        }

        location /unix {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock:/;
            proxy_set_header X-Real-IP 192.0.2.1;
        }

        location /ip {
            proxy_pass http://127.0.0.1:8080/;
            proxy_set_header X-Real-IP 192.0.2.1;
        }
    }
}

EOF

$t->write_file('1', '');
$t->write_file('2', '');
$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/1') !~ /X-IP: 127.0.0.1/m;

$t->plan(4);

###############################################################################

like(http_get('/unix/2'), qr/X-IP: 192.0.2.1/, 'realip unix');
unlike(http_get('/unix/1'), qr/X-IP: 192.0.2.1/, 'realip unix - no match');

like(http_get('/ip/1'), qr/X-IP: 192.0.2.1/, 'realip hostname');
unlike(http_get('/ip/2'), qr/X-IP: 192.0.2.1/, 'realip hostname - no match');

###############################################################################
