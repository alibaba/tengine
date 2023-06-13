#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for auth_delay directive using auth basic module.

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

my $t = Test::Nginx->new()->has(qw/http auth_basic/)
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
            auth_delay           2s;

            auth_basic           "closed site";
            auth_basic_user_file %%TESTDIR%%/htpasswd;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('htpasswd', 'user:' . '{PLAIN}good' . "\n");

$t->run()->plan(4);

###############################################################################

my $t1 = time();
like(http_get_auth('/', 'user', 'bad'), qr/401 Unauthorize/, 'not authorized');
cmp_ok(time() - $t1, '>=', 2, 'auth delay');

$t1 = time();
like(http_get_auth('/', 'user', 'good'), qr/200 OK/, 'authorized');
cmp_ok(time() - $t1, '<', 2, 'no delay');

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
