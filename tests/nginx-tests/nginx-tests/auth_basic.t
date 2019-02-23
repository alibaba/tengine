#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for auth basic module.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http auth_basic/)->plan(21)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            auth_basic           "closed site";
            auth_basic_user_file %%TESTDIR%%/htpasswd;

            location /inner {
                auth_basic off;
                alias %%TESTDIR%%/;
            }
        }
    }
}

EOF

$t->write_file('index.html', 'SEETHIS');

$t->write_file(
	'htpasswd',
	'crypt:' . crypt('password', 'salt') . "\n" .
	'crypt1:' . crypt('password', '$1$salt$') . "\n" .
	'crypt2:' . '$1$' . "\n" .
	'apr1:' . '$apr1$salt$Xxd1irWT9ycqoYxGFn4cb.' . "\n" .
	'apr12:' . '$apr1$' . "\n" .
	'plain:' . '{PLAIN}password' . "\n" .
	'ssha:' . '{SSHA}yI6cZwQadOA1e+/f+T+H3eCQQhRzYWx0' . "\n" .
	'ssha2:' . '{SSHA}_____wQadOA1e+/f+T+H3eCQQhRzYWx0' . "\n" .
	'ssha3:' . '{SSHA}Zm9vCg==' . "\n" .
	'sha:' . '{SHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g=' . "\n" .
	'sha2:' . '{SHA}_____Mm5Pz8GgiULbPgzG37mj9g=' . "\n" .
	'sha3:' . '{SHA}Zm9vCg==' . "\n"
);

$t->run();

###############################################################################

like(http_get('/'), qr!401 Unauthorized!ms, 'rejects unathorized');

SKIP: {

skip 'no crypt on win32', 5 if $^O eq 'MSWin32';

like(http_get_auth('/', 'crypt', 'password'), qr!SEETHIS!, 'normal crypt');
unlike(http_get_auth('/', 'crypt', '123'), qr!SEETHIS!, 'normal wrong');

like(http_get_auth('/', 'crypt1', 'password'), qr!SEETHIS!, 'crypt $1$ (md5)');
unlike(http_get_auth('/', 'crypt1', '123'), qr!SEETHIS!, 'crypt $1$ wrong');

like(http_get_auth('/', 'crypt2', '1'), qr!401 Unauthorized!,
	'crypt $1$ broken');

}

like(http_get_auth('/', 'apr1', 'password'), qr!SEETHIS!, 'apr1 md5');
like(http_get_auth('/', 'plain', 'password'), qr!SEETHIS!, 'plain password');
like(http_get_auth('/', 'ssha', 'password'), qr!SEETHIS!, 'ssha');
like(http_get_auth('/', 'sha', 'password'), qr!SEETHIS!, 'sha');

unlike(http_get_auth('/', 'apr1', '123'), qr!SEETHIS!, 'apr1 md5 wrong');
unlike(http_get_auth('/', 'plain', '123'), qr!SEETHIS!, 'plain wrong');
unlike(http_get_auth('/', 'ssha', '123'), qr!SEETHIS!, 'ssha wrong');
unlike(http_get_auth('/', 'sha', '123'), qr!SEETHIS!, 'sha wrong');

like(http_get_auth('/', 'apr12', '1'), qr!401 Unauthorized!, 'apr1 md5 broken');
like(http_get_auth('/', 'ssha2', '1'), qr!401 Unauthorized!, 'ssha broken 1');
like(http_get_auth('/', 'ssha3', '1'), qr!401 Unauthorized!, 'ssha broken 2');
like(http_get_auth('/', 'sha2', '1'), qr!401 Unauthorized!, 'sha broken 1');
like(http_get_auth('/', 'sha3', '1'), qr!401 Unauthorized!, 'sha broken 2');

like(http_get_auth('/', 'notfound', '1'), qr!401 Unauthorized!, 'not found');
like(http_get('/inner/'), qr!SEETHIS!, 'inner off');

###############################################################################

sub http_get_auth {
	my ($url, $user, $password) = @_;

	my $auth = encode_base64($user . ':' . $password, '');

	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Authorization: Basic $auth

EOF
}

###############################################################################
