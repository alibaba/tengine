#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail pop3 module.

###############################################################################

use warnings;
use strict;

use Test::More;

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

my $t = Test::Nginx->new()->has(qw/mail pop3 http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    proxy_timeout  15s;
    auth_http  http://127.0.0.1:8080/mail/auth;

    server {
        listen     127.0.0.1:8110;
        protocol   pop3;
        pop3_auth  plain apop cram-md5 external;
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
            add_header Auth-Port %%PORT_8111%%;
            add_header Auth-Pass $passw;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

$t->run_daemon(\&Test::Nginx::POP3::pop3_test_daemon);
$t->run()->plan(28);

$t->waitforsocket('127.0.0.1:' . port(8111));

###############################################################################

my $s = Test::Nginx::POP3->new();
$s->ok('greeting');

# user / pass

$s->send('USER test@example.com');
$s->ok('user');

$s->send('PASS secret');
$s->ok('pass');

# apop

$s = Test::Nginx::POP3->new();
$s->check(qr/<.*\@.*>/, 'apop salt');

$s->send('APOP test@example.com ' . ('1' x 32));
$s->check(qr/^-ERR/, 'apop error');

$s->send('APOP test@example.com ' . ('0' x 32));
$s->ok('apop');

# auth capabilities

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH');
$s->ok('auth');

is(get_auth_caps($s), 'PLAIN:LOGIN:CRAM-MD5:EXTERNAL', 'auth capabilities');

# auth plain

$s = Test::Nginx::POP3->new();
$s->read();

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

# auth cram-md5

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH CRAM-MD5');
$s->check(qr/\+ /, 'auth cram-md5 challenge');

$s->send(encode_base64('test@example.com ' . ('0' x 32), ''));
$s->ok('auth cram-md5');

# auth external

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH EXTERNAL');
$s->check(qr/\+ VXNlcm5hbWU6/, 'auth external challenge');

$s->send(encode_base64('test@example.com', ''));
$s->ok('auth external');

# auth external with username

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH EXTERNAL ' . encode_base64('test@example.com', ''));
$s->ok('auth external with username');

# pipelining

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('INVALID COMMAND WITH ARGUMENTS' . CRLF
	. 'NOOP');
$s->check(qr/^-ERR/, 'pipelined invalid command');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.0');

$s->ok('pipelined noop after invalid command');

}

$s->send('USER test@example.com' . CRLF
	. 'PASS secret' . CRLF
	. 'QUIT');
$s->ok('pipelined user');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.0');

$s->ok('pipelined pass');
$s->ok('pipelined quit');

}

$s = Test::Nginx::POP3->new();
$s->read();

$s->send('AUTH LOGIN' . CRLF
	. encode_base64('test@example.com', '') . CRLF
	. encode_base64('secret', ''));
$s->check(qr/\+ VXNlcm5hbWU6/, 'pipelined auth username challenge');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.0');

$s->check(qr/\+ UGFzc3dvcmQ6/, 'pipelined auth password challenge');
$s->ok('pipelined auth');

}

###############################################################################

sub get_auth_caps {
	my ($s) = @_;
	my @meth;

	while ($s->read()) {
		last if /^\./;
		push @meth, $1 if /(.*?)\x0d\x0a?/ms;
	}
	join ':', @meth;
}

###############################################################################
