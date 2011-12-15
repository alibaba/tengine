#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail pop3 module.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket;
use MIME::Base64;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::POP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()
	->has(qw/mail pop3 http rewrite/)->plan(8)
	->run_daemon(\&Test::Nginx::POP3::pop3_test_daemon)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon         off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;

    server {
        listen     127.0.0.1:8110;
        protocol   pop3;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            set $reply ERROR;

            if ($http_auth_smtp_to ~ example.com) {
                set $reply OK;
            }

            set $userpass "$http_auth_user:$http_auth_pass";
            if ($userpass ~ '^test@example.com:secret$') {
                set $reply OK;
            }

            add_header Auth-Status $reply;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port 8111;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

###############################################################################

my $s = Test::Nginx::POP3->new();
$s->ok('greeting');

# auth plain

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0bad", ''));
$s->check(qr/^-ERR/, 'auth plain with bad password');

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->ok('auth plain');

# auth login simple

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH LOGIN');
$s->check(qr/\+ VXNlcm5hbWU6/, 'auth login username challenge');

$s->send(encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login simple');

# auth login with username

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH LOGIN ' . encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login with username password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login with username');

###############################################################################
