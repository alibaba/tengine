#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for mail max_errors.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;
use Test::Nginx::POP3;
use Test::Nginx::SMTP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()->has(qw/mail imap pop3 smtp/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    auth_http  http://127.0.0.1:8080; # unused

    max_errors 2;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;
    }

    server {
        listen     127.0.0.1:8110;
        protocol   pop3;
    }

    server {
        listen     127.0.0.1:8025;
        protocol   smtp;
    }
}

EOF

$t->run()->plan(18);

###############################################################################

# imap

my $s = Test::Nginx::IMAP->new();
$s->read();

$s->send('a01 FOO');
$s->check(qr/^a01 BAD/, 'imap first error');
$s->send('a02 BAR');
$s->check(qr/^a02 BAD/, 'imap second error');
$s->send('a03 BAZZ');
$s->check(qr/^$/, 'imap max errors');

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('a01 FOO' . CRLF . 'a02 BAR' . CRLF . 'a03 BAZZ');
$s->check(qr/^a01 BAD/, 'imap pipelined first error');
$s->check(qr/^a02 BAD/, 'imap pipelined second error');
$s->check(qr/^$/, 'imap pipelined max errors');

# pop3

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('FOO');
$s->check(qr/^-ERR/, 'pop3 first error');
$s->send('BAR');
$s->check(qr/^-ERR/, 'pop3 second error');
$s->send('BAZZ');
$s->check(qr/^$/, 'pop3 max errors');

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('FOO' . CRLF . 'BAR' . CRLF . 'BAZZ');
$s->check(qr/^-ERR/, 'pop3 pipelined first error');
$s->check(qr/^-ERR/, 'pop3 pipelined second error');
$s->check(qr/^$/, 'pop3 pipelined max errors');

# smtp

$s = Test::Nginx::SMTP->new();
$s->read();

$s->send('FOO');
$s->check(qr/^5.. /, 'smtp first error');
$s->send('BAR');
$s->check(qr/^5.. /, 'smtp second error');
$s->send('BAZZ');
$s->check(qr/^$/, 'smtp max errors');

$s = Test::Nginx::SMTP->new();
$s->read();

$s->send('FOO' . CRLF . 'BAR' . CRLF . 'BAZZ');
$s->check(qr/^5.. /, 'smtp pipelined first error');
$s->check(qr/^5.. /, 'smtp pipelined second error');
$s->check(qr/^$/, 'smtp pipelined max errors');

###############################################################################
