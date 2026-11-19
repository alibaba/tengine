#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sai Krishna Kumar Reddy YADAMAKANTI
# (C) Nginx, Inc.

# Tests for nginx dav module.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http dav/)->plan(94);

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

        location /full/ {
            dav_methods PUT DELETE MKCOL COPY MOVE;
            create_full_put_path on;
        }

        location /min3/ {
            dav_methods PUT DELETE MKCOL COPY MOVE;
            min_delete_depth 3;
        }

        location /min0/ {
            dav_methods PUT DELETE MKCOL COPY MOVE;
            min_delete_depth 0;
        }

        location /access/ {
            dav_methods PUT DELETE MKCOL COPY MOVE;
            dav_access user:rw group:r all:r;
        }
    }
}

EOF

$t->run();

###############################################################################

my $r;

# basic tests

$r = http_put('/file', '0123456789');
like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'put file');
is(-s $t->testdir() . '/file', 10, 'put file size');

$r = http_put('/file', '');
like($r, qr/204 No Content/, 'put file again');
unlike($r, qr/Content-Length|Transfer-Encoding/, 'no length in 204');
is(-s $t->testdir() . '/file', 0, 'put file again size');

$r = http_delete('/file', 'Content-Length: 0');
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

$r = http_put('/file%20sp', '0123456789');
like($r, qr!Location: /file%20sp\x0d?$!ms, 'put file escaped');

# 201 replies contain body, response should indicate it's empty

$r = http_mkcol('/test/');
like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'mkcol');

SKIP: {
skip 'perl too old', 1 if !$^V or $^V lt v5.12.0;

like($r, qr!(?(?{ $r =~ /Location/ })Location: /test/)!, 'mkcol location');

}

$r = http_copy('/test/', '/test-moved/');
like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'copy dir');

$r = http_move('/test/', '/test-moved/');
like($r, qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'move dir');

$r = http_copy('/file', '/file-moved%20escape');
like($r, qr/204 No Content/, 'copy file escaped');
is(-s $t->testdir() . '/file-moved escape', 10, 'file copied unescaped');

$t->write_file('file.exist', join '', (1 .. 42));

$r = http_copy('/file', '/file.exist');
like($r, qr/204 No Content/, 'copy file overwrite');
is(-s $t->testdir() . '/file.exist', 10, 'target file truncated');

$r = http_put('/i/alias', '0123456789');
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
MOVE /file HTTP/1.1
Host: localhost
Destination: /file_dst
Connection: close
Content-Length: 10

EOF

like($r, qr/415/, 'move body');

$r = http(<<EOF . '0123456789');
DELETE /file HTTP/1.1
Host: localhost
Connection: close
Content-Length: 10

EOF

like($r, qr/415 Unsupported/, 'delete body');

my $chunked = 'a' . CRLF . '0123456789' . CRLF . '0' . CRLF . CRLF;

$r = http(<<EOF . $chunked);
MKCOL /test/ HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF

like($r, qr/415 Unsupported/, 'mkcol body chunked');

$r = http(<<EOF . $chunked);
COPY /file HTTP/1.1
Host: localhost
Destination: /file.exist
Connection: close
Transfer-Encoding: chunked

EOF

like($r, qr/415 Unsupported/, 'copy body chunked');

$r = http(<<EOF . $chunked);
MOVE /file HTTP/1.1
Host: localhost
Destination: /file_dst
Connection: close
Transfer-Encoding: chunked

EOF

like($r, qr/415/, 'move body chunked');

$r = http(<<EOF . $chunked);
DELETE /file HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF

like($r, qr/415 Unsupported/, 'delete body chunked');

# PUT edge cases

$r = http_put('/trailing/', '0123456789');
like($r, qr/409/, 'put to collection uri');

$r = http_put('/range_file', '0123456789', 'Content-Range: bytes 0-9/20');
like($r, qr/501/, 'put with content-range');

$r = http_put('/dated_file', 'dated', 'Date: Thu, 01 Jan 2026 00:00:00 GMT');
like($r, qr/201 Created/, 'put with valid date header');

$r = http_put('/baddate_file', 'baddt', 'Date: invalid-date-value');
like($r, qr/201 Created/, 'put with invalid date header');

mkdir($t->testdir() . '/existdir');

$r = http_put('/existdir', 'data');
like($r, qr/409/, 'put over existing directory');

$r = http_put('/full/a/b/c/deep_file', 'deep');
like($r, qr/201 Created/, 'put create full path');
ok(-f $t->testdir() . '/full/a/b/c/deep_file', 'put create full path exists');

$r = http_put('/noparent/sub/file', 'fail');
like($r, qr/(?:409|500)/, 'put without full path fails');

$r = http_put('/zerofile', '');
like($r, qr/201 Created/, 'put zero-length new file');

# DELETE edge cases

$r = http_delete('/nonexistent', 'Content-Length: 0');
like($r, qr/404/, 'delete non-existent');

mkdir($t->testdir() . '/deldir_noslash');
$t->write_file('deldir_noslash/f', 'x');

$r = http_delete('/deldir_noslash', 'Content-Length: 0');
like($r, qr/409/, 'delete dir without trailing slash');

mkdir($t->testdir() . '/deldir');
$t->write_file('deldir/f1', 'x');

$r = http_delete('/deldir/');
like($r, qr/204 No Content/, 'delete dir with trailing slash');
ok(!-d $t->testdir() . '/deldir', 'delete dir removed');

mkdir($t->testdir() . '/nested');
mkdir($t->testdir() . '/nested/sub');
$t->write_file('nested/a', 'x');
$t->write_file('nested/sub/b', 'x');

$r = http_delete('/nested/');
like($r, qr/204 No Content/, 'delete nested directory');
ok(!-d $t->testdir() . '/nested', 'delete nested removed');

# Depth header

mkdir($t->testdir() . '/depthdir');
$t->write_file('depthdir/f', 'x');

$r = http_delete('/depthdir/', 'Depth: 0');
like($r, qr/400/, 'delete dir depth 0');

$r = http_delete('/depthdir/', 'Depth: 1');
like($r, qr/400/, 'delete dir depth 1');

$t->write_file('depthfile', 'x');

$r = http_delete('/depthfile', 'Depth: 1');
like($r, qr/400/, 'delete file depth 1');

$t->write_file('depthfile0', 'x');

$r = http_delete('/depthfile0', 'Depth: 0');
like($r, qr/204 No Content/, 'delete file depth 0');

$t->write_file('depthfile_inf', 'x');

$r = http_delete('/depthfile_inf', 'Depth: infinity');
like($r, qr/204 No Content/, 'delete file depth infinity');

$t->write_file('baddepth', 'x');

$r = http_delete('/baddepth', 'Depth: bogus');
like($r, qr/400/, 'delete invalid depth header');

$t->write_file('depth2', 'x');

$r = http_delete('/depth2', 'Depth: 2');
like($r, qr/400/, 'delete depth 2 invalid');

# min_delete_depth

mkdir($t->testdir() . '/min3');
$t->write_file('min3/shallow', 'x');

$r = http_delete('/min3/shallow');
like($r, qr/409/, 'min_delete_depth too shallow');

mkdir($t->testdir() . '/min3/a');
mkdir($t->testdir() . '/min3/a/b');
$t->write_file('min3/a/b/deep', 'x');

$r = http_delete('/min3/a/b/deep');
like($r, qr/204 No Content/, 'min_delete_depth deep enough');

mkdir($t->testdir() . '/min0');
$t->write_file('min0/top', 'x');

$r = http_delete('/min0/top');
like($r, qr/204 No Content/, 'min_delete_depth 0');

# MKCOL edge cases

$r = http_mkcol('/no_slash');
like($r, qr/409/, 'mkcol without trailing slash');

http_mkcol('/newcol/');
$r = http_mkcol('/newcol/');
like($r, qr/405/, 'mkcol existing directory');

$r = http_mkcol('/nonexist_parent/child/');
like($r, qr/409/, 'mkcol missing parent');

# Destination header validation

$t->write_file('src_file', 'COPYDATA');

$r = http(<<EOF);
COPY /src_file HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/400/, 'copy no destination');

$r = http_copy('/src_file', 'ftp://localhost/bad_scheme');
like($r, qr/400/, 'copy invalid destination scheme');

$r = http_copy('/src_file', 'http://otherhost/file');
like($r, qr/400/, 'copy different host');

$r = http_copy('/src_file', 'http://localhost/full_url_copy');
like($r, qr/20[14]/, 'copy with full url destination');

$r = http_copy('/src_file', 'http://localhost:8080/port_copy');
like($r, qr/20[14]/, 'copy with port in destination');

$r = http_copy('/src_file', 'http://localhost');
like($r, qr/400/, 'copy destination no path after host');

$r = http(<<EOF);
MOVE /src_file HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/400/, 'move no destination');

# Overwrite header

$t->write_file('src_ow', 'OWDATA');
$t->write_file('existing_dst', 'OLD');

$r = http_copy('/src_ow', '/existing_dst', 'Overwrite: F');
like($r, qr/412/, 'copy overwrite false');
is($t->read_file('existing_dst'), 'OLD', 'copy overwrite false preserved');

$t->write_file('existing_dst2', 'OLD2');

$r = http_copy('/src_ow', '/existing_dst2', 'Overwrite: f');
like($r, qr/412/, 'copy overwrite lowercase f');

$r = http_copy('/src_ow', '/existing_dst', 'Overwrite: T');
like($r, qr/204 No Content/, 'copy overwrite true');
is($t->read_file('existing_dst'), 'OWDATA', 'copy overwrite true replaced');

$t->write_file('ow_lower', 'OLD');

$r = http_copy('/src_ow', '/ow_lower', 'Overwrite: t');
like($r, qr/204 No Content/, 'copy overwrite lowercase t');

$r = http_copy('/src_ow', '/inv_ow_dst', 'Overwrite: X');
like($r, qr/400/, 'copy invalid overwrite');

$r = http_copy('/src_ow', '/inv_ow_dst2', 'Overwrite: TRUE');
like($r, qr/400/, 'copy invalid overwrite multi-char');

# COPY Depth header

$r = http_copy('/src_ow', '/depth0_copy', 'Depth: 0');
like($r, qr/204 No Content/, 'copy file depth 0');

$r = http_copy('/src_ow', '/depth1_copy', 'Depth: 1');
like($r, qr/400/, 'copy depth 1 invalid');

# collection/non-collection mismatch

mkdir($t->testdir() . '/srcdir_mm');
$t->write_file('srcdir_mm/inner', 'INNER');

$r = http_copy('/srcdir_mm/', '/mismatch_noncol');
like($r, qr/409/, 'copy collection to non-collection');

$r = http_copy('/src_ow', '/mismatch_col/');
like($r, qr/409/, 'copy non-collection to collection');

# directory tree operations

mkdir($t->testdir() . '/srcdir_tree');
mkdir($t->testdir() . '/srcdir_tree/subdir');
$t->write_file('srcdir_tree/file1', 'FILE1');
$t->write_file('srcdir_tree/subdir/file2', 'FILE2');

$r = http_copy('/srcdir_tree/', '/dstdir_tree/');
like($r, qr/201 Created/, 'copy directory tree');
is($t->read_file('dstdir_tree/file1'), 'FILE1', 'copy tree file');
is($t->read_file('dstdir_tree/subdir/file2'), 'FILE2', 'copy tree subdir file');

mkdir($t->testdir() . '/ow_src');
$t->write_file('ow_src/data', 'NEWDATA');
mkdir($t->testdir() . '/ow_dst');
$t->write_file('ow_dst/old', 'OLDDATA');

$r = http_copy('/ow_src/', '/ow_dst/', 'Overwrite: T');
like($r, qr/201 Created/, 'copy dir overwrite existing');
is($t->read_file('ow_dst/data'), 'NEWDATA', 'copy dir overwrite content');

$r = http_copy('/nonexistent_src', '/some_dst');
like($r, qr/404/, 'copy source not found');

mkdir($t->testdir() . '/existing_dir_dst');

$r = http_copy('/src_ow', 'http://localhost/existing_dir_dst');
like($r, qr/409/, 'copy to existing dir no slash');

# MOVE

$t->write_file('moveme', 'MOVEDATA');

$r = http_move('/moveme', '/moved');
like($r, qr/204 No Content/, 'move file');
ok(!-f $t->testdir() . '/moveme', 'move file source removed');
is($t->read_file('moved'), 'MOVEDATA', 'move file content');

$t->write_file('movedepth', 'x');

$r = http_move('/movedepth', '/movedepth_dst', 'Depth: 0');
like($r, qr/400/, 'move depth 0 invalid');

mkdir($t->testdir() . '/movedir_nested');
mkdir($t->testdir() . '/movedir_nested/sub');
$t->write_file('movedir_nested/a', 'A');
$t->write_file('movedir_nested/sub/b', 'B');
mkdir($t->testdir() . '/movedir_nested_dst');

$r = http_move('/movedir_nested/', '/movedir_nested_dst/');
like($r, qr/201 Created/, 'move nested directory');
ok(!-d $t->testdir() . '/movedir_nested', 'move nested source removed');

# dav_access

mkdir($t->testdir() . '/access');

$r = http_put('/access/afile', 'accessdata');
like($r, qr/201 Created/, 'dav_access put');

SKIP: {
skip 'permissions on win32', 1 if $^O eq 'MSWin32';

my $mode = (stat($t->testdir() . '/access/afile'))[2] & 07777;
is($mode & 0644, 0644, 'dav_access file permissions');

}

$r = http_mkcol('/access/subdir/');
like($r, qr/201 Created/, 'dav_access mkcol');

SKIP: {
skip 'permissions on win32', 1 if $^O eq 'MSWin32';

my $mode = (stat($t->testdir() . '/access/subdir'))[2] & 07777;
ok($mode & 0755, 'dav_access mkcol permissions');

}

###############################################################################

sub http_put {
	my ($uri, $body, $extra) = @_;
	my $length = length($body);
	my $headers = <<EOF;
PUT $uri HTTP/1.1
Host: localhost
Connection: close
Content-Length: $length
EOF

	if ($extra) {
		$headers .= $extra . CRLF;
	}

	http($headers . CRLF . $body);
}

sub http_delete {
	my ($uri, $extra) = @_;
	$extra = '' if !defined $extra;
	http(<<EOF);
DELETE $uri HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

sub http_mkcol {
	my ($uri) = @_;
	http(<<EOF);
MKCOL $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

sub http_copy {
	my ($uri, $destination, $extra) = @_;
	$extra = '' if !defined $extra;
	http(<<EOF);
COPY $uri HTTP/1.1
Host: localhost
Connection: close
Destination: $destination
$extra

EOF
}

sub http_move {
	my ($uri, $destination, $extra) = @_;
	$extra = '' if !defined $extra;
	http(<<EOF);
MOVE $uri HTTP/1.1
Host: localhost
Connection: close
Destination: $destination
$extra

EOF
}

###############################################################################
