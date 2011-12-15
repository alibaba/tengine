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

my $t = Test::Nginx->new()->has(qw/http auth_basic/)->plan(11)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

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
        }
    }
}

EOF

my $d = $t->testdir();

$t->write_file('index.html', 'SEETHIS');

$t->write_file(
	'htpasswd',
	'crypt:' . crypt('password', 'salt') . "\n" .
	'crypt1:' . crypt('password', '$1$salt$') . "\n" .
	'apr1:' . '$apr1$salt$Xxd1irWT9ycqoYxGFn4cb.' . "\n" .
	'plain:' . '{PLAIN}password' . "\n" .
	'ssha:' . '{SSHA}yI6cZwQadOA1e+/f+T+H3eCQQhRzYWx0' . "\n"
);

$t->run();

###############################################################################

like(http_get('/'), qr!401 Unauthorized!ms, 'rejects unathorized');

like(http_get_auth('/', 'crypt', 'password'), qr!SEETHIS!, 'normal crypt');
unlike(http_get_auth('/', 'crypt', '123'), qr!SEETHIS!, 'normal wrong');

like(http_get_auth('/', 'crypt1', 'password'), qr!SEETHIS!, 'crypt $1$ (md5)');
unlike(http_get_auth('/', 'crypt1', '123'), qr!SEETHIS!, 'crypt $1$ wrong');

like(http_get_auth('/', 'apr1', 'password'), qr!SEETHIS!, 'apr1 md5');
like(http_get_auth('/', 'plain', 'password'), qr!SEETHIS!, 'plain password');

SKIP: {
	# SHA1 may not be available unless we have OpenSSL

	skip 'no sha1', 1 unless $t->has_module('--with-http_ssl_module')
		or $t->has_module('--with-sha1')
		or $t->has_module('--with-openssl');

	like(http_get_auth('/', 'ssha', 'password'), qr!SEETHIS!, 'ssha');
}

unlike(http_get_auth('/', 'apr1', '123'), qr!SEETHIS!, 'apr1 md5 wrong');
unlike(http_get_auth('/', 'plain', '123'), qr!SEETHIS!, 'plain wrong');
unlike(http_get_auth('/', 'ssha', '123'), qr!SEETHIS!, 'ssha wrong');

###############################################################################

sub http_get_auth {
	my ($url, $user, $password) = @_;

	my $auth = encode_base64($user . ':' . $password);

        my $r = http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Authorization: Basic $auth

EOF
}

###############################################################################
