#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx dav module with utf8 encoded names.

###############################################################################

use warnings;
use strict;

use Test::More;

use Encode qw/ encode /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require Win32API::File if $^O eq 'MSWin32'; };
plan(skip_all => 'Win32API::File not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http dav/)->plan(16);

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

local $TODO = 'not yet' if $^O eq 'MSWin32' and !$t->has_version('1.23.4');

my $d = $t->testdir();
my $r;

my $file = "file-%D0%BC%D0%B8";
my $file_path = "file-\x{043c}\x{0438}";

$r = http(<<EOF . '0123456789');
PUT /$file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'put file');
ok(fileexists("$d/$file_path"), 'put file exist');

$r = http(<<EOF);
COPY /$file HTTP/1.1
Host: localhost
Destination: /$file-moved
Connection: close

EOF

like($r, qr/204 No Content/, 'copy file');
ok(fileexists("$d/$file_path-moved"), 'copy file exist');

$r = http(<<EOF);
MOVE /$file HTTP/1.1
Host: localhost
Destination: /$file-moved
Connection: close

EOF

like($r, qr/204 No Content/, 'move file');
ok(!fileexists("$d/$file_path"), 'file moved');

$r = http(<<EOF);
DELETE /$file-moved HTTP/1.1
Host: localhost
Connection: close
Content-Length: 0

EOF

like($r, qr/204 No Content/, 'delete file');
ok(!fileexists("$d/$file_path-moved"), 'file deleted');

my $dir = "dir-%D0%BC%D0%B8";
my $dir_path = "dir-\x{043c}\x{0438}";

$r = http(<<EOF);
MKCOL /$dir/ HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'mkcol');
ok(fileexists("$d/$dir_path"), 'mkcol exist');

$r = http(<<EOF);
COPY /$dir/ HTTP/1.1
Host: localhost
Destination: /$dir-moved/
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'copy dir');
ok(fileexists("$d/$dir_path-moved"), 'copy dir exist');

$r = http(<<EOF);
MOVE /$dir/ HTTP/1.1
Host: localhost
Destination: /$dir-moved/
Connection: close

EOF

like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'move dir');
ok(!fileexists("$d/$dir_path"), 'dir moved');

$r = http(<<EOF);
DELETE /$dir-moved/ HTTP/1.1
Host: localhost
Connection: close

EOF

unlike($r, qr/200 OK.*Content-Length|Transfer-Encoding/ms, 'delete dir');
ok(!fileexists("$d/$dir_path-moved"), 'dir deleted');

###############################################################################

sub fileexists {
	my ($path) = @_;

	return -e $path if $^O ne 'MSWin32';

	$path = encode("UTF-16LE", $path . "\0");
	my $attr = Win32API::File::GetFileAttributesW($path);
	return 0 if $attr == Win32API::File::INVALID_HANDLE_VALUE();
	return $attr;
}

###############################################################################
