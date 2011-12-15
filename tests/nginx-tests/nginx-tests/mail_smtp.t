#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail smtp module.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::SMTP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()
	->has(qw/mail smtp http rewrite/)->plan(25)
	->run_daemon(\&Test::Nginx::SMTP::smtp_test_daemon)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon         off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;
    xclient    off;

    server {
        listen     127.0.0.1:8025;
        protocol   smtp;
        smtp_auth  login plain none;
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
            add_header Auth-Port 8026;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

###############################################################################

my $s = Test::Nginx::SMTP->new();
$s->check(qr/^220 /, "greeting");

$s->send('EHLO example.com');
$s->check(qr/^250 /, "ehlo");

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0bad", ''));
$s->check(qr/^5.. /, 'auth plain with bad password');

$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('auth plain');

# We are talking to backend from this point

$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->ok('mail from after auth');

$s->send('RSET');
$s->ok('rset');

$s->send('MAIL FROM:<test@xn--e1afmkfd.xn--80akhbyknj4f> SIZE=100');
$s->ok("idn mail from (example.test in russian)");

$s->send('QUIT');
$s->ok("quit");

# Try auth login in simple form

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('AUTH LOGIN');
$s->check(qr/^334 VXNlcm5hbWU6/, 'auth login simple username challenge');
$s->send(encode_base64('test@example.com', ''));
$s->check(qr/^334 UGFzc3dvcmQ6/, 'auth login simple password challenge');
$s->send(encode_base64('secret', ''));
$s->authok('auth login simple');

# Try auth plain with username.  Details:
#
# [MS-XLOGIN]: SMTP Protocol AUTH LOGIN Extension Specification
# http://download.microsoft.com/download/5/D/D/5DD33FDF-91F5-496D-9884-0A0B0EE698BB/%5BMS-XLOGIN%5D.pdf

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('AUTH LOGIN ' . encode_base64('test@example.com', ''));
$s->check(qr/^334 UGFzc3dvcmQ6/, 'auth login with username password challenge');
$s->send(encode_base64('secret', ''));
$s->authok('auth login with username');

# Try auth plain with pipelining

TODO: {
local $TODO = 'pipelining not in official nginx';
local $SIG{__WARN__} = sub {};

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('INVALID COMMAND WITH ARGUMENTS' . CRLF
	. 'RSET');
$s->read();
$s->ok('pipelined rset after invalid command');

$s->send('AUTH PLAIN '
	. encode_base64("\0test\@example.com\0bad", '') . CRLF
	. 'MAIL FROM:<test@example.com> SIZE=100');
$s->read();
$s->ok('mail from after failed pipelined auth');

$s->send('AUTH PLAIN '
	. encode_base64("\0test\@example.com\0secret", '') . CRLF
	. 'MAIL FROM:<test@example.com> SIZE=100');
$s->read();
$s->ok('mail from after pipelined auth');

}

# Try auth none

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->ok('auth none - mail from');

$s->send('RCPT TO:<test@example.com>');
$s->ok('auth none - rcpt to');

$s->send('RSET');
$s->ok('auth none - rset, should go to backend');

# Auth none with pipelining

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('MAIL FROM:<test@example.com> SIZE=100' . CRLF
	. 'RCPT TO:<test@example.com>' . CRLF
	. 'RSET');

$s->ok('pipelined mail from');

TODO: {
local $TODO = 'pipelining not in official nginx';
local $SIG{__WARN__} = sub {};

$s->ok('pipelined rcpt to');
$s->ok('pipelined rset');

}

# Connection must stay even if error returned to rcpt to command

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();

$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read(); # skip mail from reply

$s->send('RCPT TO:<example.com>');
$s->check(qr/^5.. /, "bad rcpt to");

$s->send('RCPT TO:<test@example.com>');
$s->ok('good rcpt to');

# Make sure command splitted into many packets processed correctly

$s = Test::Nginx::SMTP->new();
$s->read();

log_out('HEL');
$s->print('HEL');
$s->send('O example.com');
$s->ok('splitted command');

###############################################################################
