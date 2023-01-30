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

my $t = Test::Nginx->new()->has(qw/http dav/)->plan(28);

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

        absolute_redirect off;

        location / {
            dav_methods PUT DELETE MKCOL COPY MOVE;
        }

        location /i/ {
            alias %%TESTDIR%%/;
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

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.0');

$r = http(<<EOF . '0123456789');
PUT /file%20sp HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr!Location: /file%20sp\x0d?$!ms, 'put file escaped');

}

# 201 replies contain body, response should indicate it's empty

$r = http(<<EOF);
MKCOL /test/ HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'mkcol');

SKIP: {
skip 'perl too old', 1 if !$^V or $^V lt v5.12.0;

like($r, qr!(?(?{ $r =~ /Location/ })Location: /test/)!, 'mkcol location');

}

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
is(-s $t->testdir() . '/file-moved escape', 10, 'file copied unescaped');

$t->write_file('file.exist', join '', (1 .. 42));

$r = http(<<EOF);
COPY /file HTTP/1.1
Host: localhost
Destination: /file.exist
Connection: close

EOF

like($r, qr/204 No Content/, 'copy file overwrite');
is(-s $t->testdir() . '/file.exist', 10, 'target file truncated');

$r = http(<<EOF . '0123456789');
PUT /i/alias HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'put alias');
like($r, qr!Location: /i/alias\x0d?$!ms, 'location alias');
is(-s $t->testdir() . '/alias', 10, 'put alias size');

# request methods with unsupported request body

$r = http(<<EOF . '0123456789');
MKCOL /test/ HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/415 Unsupported/, 'mkcol body');

$r = http(<<EOF . '0123456789');
COPY /file HTTP/1.1
Host: localhost
Destination: /file.exist
Connection: close
Content-Length: 10

EOF

like($r, qr/415 Unsupported/, 'copy body');

$r = http(<<EOF . '0123456789');
DELETE /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/415 Unsupported/, 'delete body');

$r = http(<<EOF);
MKCOL /test/ HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

a
0123456789
0

EOF

like($r, qr/415 Unsupported/, 'mkcol body chunked');

$r = http(<<EOF);
COPY /file HTTP/1.1
Host: localhost
Destination: /file.exist
Connection: close
Transfer-Encoding: chunked

a
0123456789
0

EOF

like($r, qr/415 Unsupported/, 'copy body chunked');

$r = http(<<EOF);
DELETE /file HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

a
0123456789
0

EOF

like($r, qr/415 Unsupported/, 'delete body chunked');

###############################################################################
