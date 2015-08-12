#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx dav module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http dav/)->plan(15);

$t->write_file_expand('nginx.conf', <<'EOF');

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
            dav_methods PUT DELETE MKCOL COPY MOVE;
        }
    }
}

EOF

$t->run();

###############################################################################

my $r;

$r = http(<<EOF . '0123456789');
PUT /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'put file');
is(-s $t->testdir() . '/file', 10, 'put file size');

$r = http(<<EOF);
PUT /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 0

EOF

like($r, qr/204 No Content/, 'put file again');
unlike($r, qr/Content-Length|Transfer-Encoding/, 'no length in 204');
is(-s $t->testdir() . '/file', 0, 'put file again size');

$r = http(<<EOF);
DELETE /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 0

EOF

like($r, qr/204 No Content/, 'delete file');
unlike($r, qr/Content-Length|Transfer-Encoding/, 'no length in 204');
ok(!-f $t->testdir() . '/file', 'file deleted');

$r = http(<<EOF . '0123456789' . 'extra');
PUT /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms,
	'put file extra data');
is(-s $t->testdir() . '/file', 10,
	'put file extra data size');

# 201 replies contain body, response should indicate it's empty

$r = http(<<EOF);
MKCOL /test/ HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'mkcol');

$r = http(<<EOF);
COPY /test/ HTTP/1.1
Host: localhost
Destination: /test-moved/
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'copy dir');

$r = http(<<EOF);
MOVE /test/ HTTP/1.1
Host: localhost
Destination: /test-moved/
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'move dir');

$r = http(<<EOF);
COPY /file HTTP/1.1
Host: localhost
Destination: /file-moved%20escape
Connection: close

EOF

like($r, qr/204 No Content/, 'copy file escaped');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.9');

is(-s $t->testdir() . '/file-moved escape', 10, 'file copied unescaped');

}

###############################################################################
