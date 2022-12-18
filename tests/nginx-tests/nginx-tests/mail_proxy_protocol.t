#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for mail proxy module, PROXY protocol with realip.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::SMTP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()->has(qw/mail smtp http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    proxy_timeout             15s;
    proxy_smtp_auth           on;
    proxy_protocol            on;
    auth_http  http://127.0.0.1:8080/mail/auth;
    smtp_auth  login plain;

    server {
        listen    127.0.0.1:8025 proxy_protocol;
        protocol  smtp;

        auth_http_header  X-Type proxy;
    }

    server {
        listen    127.0.0.1:8027 proxy_protocol;
        protocol  smtp;

        set_real_ip_from  127.0.0.1/32;
        auth_http_header  X-Type realip;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            set $reply ERROR;
            set $test $http_x_type:$http_client_ip:$http_proxy_protocol_addr;

            if ($test = proxy:127.0.0.1:192.0.2.1) {
                set $reply OK;
            }

            if ($test = realip:192.0.2.1:192.0.2.1) {
                set $reply OK;
            }

            add_header Auth-Status $reply;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port %%PORT_8026%%;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

$t->run_daemon(\&Test::Nginx::SMTP::smtp_test_daemon);
$t->run()->plan(8);

$t->waitforsocket('127.0.0.1:' . port(8026));

###############################################################################

# connection with PROXY protocol

my $s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8025));
$s->send('PROXY TCP4 192.0.2.1 192.0.2.2 123 5678');
$s->check(qr/^220 /, "greeting with proxy_protocol");

$s->send('EHLO example.com');
$s->check(qr/^250 /, "ehlo with proxy_protocol");

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('auth with proxy_protocol');

$s->send('XPROXY');
$s->check(qr/^211 PROXY TCP4 127.0.0.1 127.0.0.1 \d+ \d+/,
	'proxy protocol to backend');

# connection with PROXY protocol and set_realip_from

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8027));

$s->send('PROXY TCP4 192.0.2.1 192.0.2.2 123 5678');
$s->check(qr/^220 /, "greeting with proxy_protocol and realip");

$s->send('EHLO example.com');
$s->check(qr/^250 /, "ehlo with proxy_protocol and realip");

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('auth with proxy_protocol and realip');

$s->send('XPROXY');
$s->check(qr/^211 PROXY TCP4 192.0.2.1 127.0.0.1 \d+ \d+/,
	'proxy_protocol to backend and realip');

###############################################################################
