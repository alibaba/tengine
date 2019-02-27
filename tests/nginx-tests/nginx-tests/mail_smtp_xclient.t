#!/usr/bin/perl

# (C) Maxim Dounin

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

my $t = Test::Nginx->new()->has(qw/mail smtp http rewrite/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;
    xclient    on;

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
$t->run()->waitforsocket('127.0.0.1:' . port(8026));

###############################################################################

# When XCLIENT's HELO= argument isn't used, the  following combinations may be
# send to backend with xclient on:
#
# xclient
# xclient, helo
# xclient, ehlo
# xclient, from, rcpt
# xclient, helo, from, rcpt
# xclient, ehlo, from, rcpt
#
# Test them in order.

# xclient

my $s = Test::Nginx::SMTP->new();
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('xclient');

# xclient, helo

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('HELO example.com');
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('xclient, helo');

# xclient, ehlo

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('AUTH PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->authok('xclient, ehlo');

# xclient, from, rcpt

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('MAIL FROM:<test@example.com>');
$s->read();
$s->send('RCPT TO:<test@example.com>');
$s->ok('xclient, from');

# xclient, helo, from, rcpt

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('HELO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com>');
$s->read();
$s->send('RCPT TO:<test@example.com>');
$s->ok('xclient, helo, from');

# xclient, ehlo, from, rcpt

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com>');
$s->read();
$s->send('RCPT TO:<test@example.com>');
$s->ok('xclient, ehlo, from');

###############################################################################
