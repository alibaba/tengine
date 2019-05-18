#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail imap module.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()->has(qw/mail imap http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;
        imap_auth  plain cram-md5 external;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            set $reply ERROR;
            set $passw "";

            if ($http_auth_smtp_to ~ example.com) {
                set $reply OK;
            }

            set $userpass "$http_auth_user:$http_auth_pass";
            if ($userpass ~ '^test@example.com:secret$') {
                set $reply OK;
            }

            set $userpass "$http_auth_user:$http_auth_salt:$http_auth_pass";
            if ($userpass ~ '^test@example.com:<.*@.*>:0{32}$') {
                set $reply OK;
                set $passw secret;
            }

            set $userpass "$http_auth_method:$http_auth_user:$http_auth_pass";
            if ($userpass ~ '^external:test@example.com:$') {
                set $reply OK;
                set $passw secret;
            }

            add_header Auth-Status $reply;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port %%PORT_8144%%;
            add_header Auth-Pass $passw;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

$t->run_daemon(\&Test::Nginx::IMAP::imap_test_daemon);
$t->run()->plan(14);

$t->waitforsocket('127.0.0.1:' . port(8144));

###############################################################################

my $s = Test::Nginx::IMAP->new();
$s->ok('greeting');

# bad auth

$s->send('1 AUTHENTICATE');
$s->check(qr/^\S+ BAD/, 'auth without arguments');

# auth plain

$s->send('1 AUTHENTICATE PLAIN ' . encode_base64("\0test\@example.com\0bad", ''));
$s->check(qr/^\S+ NO/, 'auth plain with bad password');

$s->send('1 AUTHENTICATE PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->ok('auth plain');

# auth login simple

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE LOGIN');
$s->check(qr/\+ VXNlcm5hbWU6/, 'auth login username challenge');

$s->send(encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login simple');

# auth login with username

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE LOGIN ' . encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login with username password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login with username');

# auth cram-md5

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE CRAM-MD5');
$s->check(qr/\+ /, 'auth cram-md5 challenge');

$s->send(encode_base64('test@example.com ' . ('0' x 32), ''));
$s->ok('auth cram-md5');

# auth external

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE EXTERNAL');
$s->check(qr/\+ VXNlcm5hbWU6/, 'auth external challenge');

$s->send(encode_base64('test@example.com', ''));
$s->ok('auth external');

# auth external with username

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE EXTERNAL ' . encode_base64('test@example.com', ''));
$s->ok('auth external with username');

###############################################################################
