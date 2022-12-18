#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx mail proxy module, the proxy_smtp_auth directive.

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
    auth_http  http://127.0.0.1:8080/mail/auth;
    smtp_auth  login plain external;

    server {
        listen     127.0.0.1:8025;
        protocol   smtp;
    }

    server {
        listen     127.0.0.1:8027;
        protocol   smtp;
        xclient    off;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            add_header Auth-Status OK;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port   %%PORT_8026%%;
            add_header Auth-Wait   1;
            return 204;
        }
    }
}

EOF

$t->run_daemon(\&Test::Nginx::SMTP::smtp_test_daemon);
$t->run()->plan(7);

$t->waitforsocket('127.0.0.1:' . port(8026));

###############################################################################

# The following combinations may be sent to backend with proxy_smtp_auth on:
#
# ehlo, xclient, auth
# ehlo, xclient, helo, auth
# ehlo, xclient, ehlo, auth
# helo, auth
# ehlo, auth
#
# Test them in order.

# ehlo, xclient, auth

my $s = Test::Nginx::SMTP->new();
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('ehlo, xclient, auth');

# ehlo, xclient, helo, auth

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('HELO example.com');
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('ehlo, xclient, helo, auth');

# ehlo, xclient, ehlo, auth

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('ehlo, xclient, ehlo, auth');

# helo, auth

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8027));
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('helo, auth');

# ehlo, auth

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8027));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('ehlo, auth');

# Try auth external

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('AUTH EXTERNAL');
$s->check(qr/^334 VXNlcm5hbWU6/, 'auth external challenge');
$s->send(encode_base64('test@example.com', ''));
$s->check(qr/^4.. /, 'auth external no password');

###############################################################################
