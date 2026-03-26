#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for autoindex module on win32.

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

eval { require Win32API::File; };
plan(skip_all => 'Win32API::File not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http autoindex charset/)->plan(9)
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
            autoindex on;
            charset utf-8;
        }
    }
}

EOF

my $d = $t->testdir();

mkdir("$d/test-dir");
$t->write_file('test-file', '');

my $file = "$d/test-file-" . ("\x{043c}\x{0438}") x 3;
win32_write_file($file, '');

my $dir = "$d/test-dir-" . ("\x{043c}\x{0438}") x 3;
win32_mkdir($dir);

my $subfile = "$dir/test-subfile-" . ("\x{043c}\x{0438}") x 3;
win32_write_file($subfile, '');

$t->run();

###############################################################################

my $r = http_get('/');

like($r, qr!href="test-file"!ms, 'file');
like($r, qr!href="test-dir/"!ms, 'directory');

like($r, qr!href="test-file-(%d0%bc%d0%b8){3}"!msi, 'utf file link');
like($r, qr!test-file-(\xd0\xbc\xd0\xb8){3}</a>!ms, 'utf file name');

like($r, qr!href="test-dir-(%d0%bc%d0%b8){3}/"!msi, 'utf dir link');
like($r, qr!test-dir-(\xd0\xbc\xd0\xb8){3}/</a>!ms, 'utf dir name');

$r = http_get('/test-dir-' . "\xd0\xbc\xd0\xb8" x 3 . '/');

like($r, qr!Index of /test-dir-(\xd0\xbc\xd0\xb8){3}/!msi, 'utf subdir index');

like($r, qr!href="test-subfile-(%d0%bc%d0%b8){3}"!msi, 'utf subdir link');
like($r, qr!test-subfile-(\xd0\xbc\xd0\xb8){3}</a>!msi, 'utf subdir name');

###############################################################################

sub win32_mkdir {
	my ($name) = @_;

	mkdir("$d/test-dir-tmp");
	Win32API::File::MoveFileW(encode("UTF-16LE","$d/test-dir-tmp\0"),
		encode("UTF-16LE", $name . "\0")) or die "$^E";
}

sub win32_write_file {
	my ($name, $data) = @_;

	my $h = Win32API::File::CreateFileW(encode("UTF-16LE", $name . "\0"),
		Win32API::File::FILE_READ_DATA()
		| Win32API::File::FILE_WRITE_DATA(), 0, [],
		Win32API::File::CREATE_NEW(), 0, []) or die $^E;

	Win32API::File::WriteFile($h, $data, 0, [], []) or die $^E;
	Win32API::File::CloseHandle($h) or die $^E;
}

###############################################################################
