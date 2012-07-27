#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx secure_link module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Digest::MD5 qw/ md5 md5_hex /;
use MIME::Base64 qw/ encode_base64 /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http secure_link/)->plan(8);

$t->set_dso("ngx_http_secure_link_module", "ngx_http_secure_link_module.so");
$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            # new style
            # /test.html?hash=BASE64URL

            secure_link      $arg_hash;
            secure_link_md5  secret$uri;

            # invalid hash
            if ($secure_link = "") {
                return 403;
            }

            # expired
            if ($secure_link = "0") {
                return 403;
            }

            # $secure_link = "1"
        }

        location = /expires.html {
            # new style with expires
            # /test.html?hash=BASE64URL&expires=12345678

            secure_link      $arg_hash,$arg_expires;
            secure_link_md5  secret$uri$arg_expires;

            # invalid hash
            if ($secure_link = "") {
                return 403;
            }

            # expired
            if ($secure_link = "0") {
                return 403;
            }

            # $secure_link = "1"
        }

        location /p/ {
            # old style
            # /p/d8e8fca2dc0f896fd7cb4cb0031ba249/test.html

            secure_link_secret secret;

            if ($secure_link = "") {
                return 403;
            }

            rewrite ^ /$secure_link break;
        }
    }
}

EOF

$t->write_file('test.html', 'PASSED');
$t->write_file('expires.html', 'PASSED');
$t->run();

###############################################################################

# new style

like(http_get('/test.html?hash=q-5vpkjBkRXXtkUMXiJVHA=='),
	qr/PASSED/, 'request md5');
like(http_get('/test.html?hash=q-5vpkjBkRXXtkUMXiJVHA'),
	qr/PASSED/, 'request md5 no padding');
like(http_get('/test.html'), qr/^HTTP.*403/, 'request no hash');

# new style with expires

my ($expires, $hash);

$expires = time() + 86400;
$hash = encode_base64url(md5("secret/expires.html$expires"));
like(http_get('/expires.html?hash=' . $hash . '&expires=' . $expires),
        qr/PASSED/, 'request md5 not expired');

$expires = time() - 86400;
$hash = encode_base64url(md5("secret/expires.html$expires"));
like(http_get('/expires.html?hash=' . $hash . '&expires=' . $expires),
        qr/^HTTP.*403/, 'request md5 expired');

# old style

like(http_get('/p/' . md5_hex('test.html' . 'secret') . '/test.html'),
	qr/PASSED/, 'request old style');
like(http_get('/p/' . md5_hex('fake') . '/test.html'), qr/^HTTP.*403/,
	'request old style fake hash');
like(http_get('/p/test.html'), qr/^HTTP.*403/, 'request old style no hash');

###############################################################################

sub encode_base64url {
    my $e = encode_base64(shift, "");
    $e =~ s/=+\z//;
    $e =~ tr[+/][-_];
    return $e;
}

###############################################################################
