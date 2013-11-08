#!/usr/bin/env perl

# (C) Maxim Dounin

# Tests for location selection on win32.

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

plan(skip_all => 'not win32')
	if $^O ne 'MSWin32' && $^O ne 'msys';

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(19)
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
            add_header X-Location root;
            return 204;
        }

        location /directory/ {
            add_header X-Location directory;
            return 204;
        }

        location /direct~1 {
        }

        location = /file {
            add_header X-Location file;
            return 204;
        }
    }
}

EOF

$t->run();

my $d = $t->testdir();
mkdir("$d/directory");

$t->write_file('directory/file', 'SEE-THIS');

###############################################################################

like(http_get('/x'), qr/X-Location: root/, 'root');

# these all are mapped to "/directory/"

like(http_get('/directory/'), qr/X-Location: directory/, 'directory');
like(http_get('/Directory/'), qr/X-Location: directory/, 'directory caseless');
like(http_get('/directory./'), qr/X-Location: directory/, 'directory dot');
like(http_get('/directory.%2ffile'), qr/X-Location: directory/,
	'directory dot encoded slash');
like(http_get('/directory::$index_allocation/'),
	qr/X-Location: directory|400 Bad/,
	'directory stream');
like(http_get('/directory::$index_allocation./'),
	qr/X-Location: directory|400 Bad/,
	'directory stream dot');
like(http_get('/directory:$i30:$index_allocation./'),
	qr/X-Location: directory|400 Bad/,
	'directory i30 stream dot');

# these looks similar, but shouldn't be mapped to "/directory/"

like(http_get('/directory../'), qr/X-Location: root/, 'directory dot dot');
like(http_get('/directory.::$index_allocation/'), qr/X-Location: root|400 Bad/,
	'directory dot stream');

# short name, should be rejected

unlike(http_get('/direct~1/file'), qr/SEE-THIS/, 'short name');
unlike(http_get('/direct~1./file'), qr/SEE-THIS/, 'short name dot');
unlike(http_get('/direct~1::$index_allocation./file'), qr/SEE-THIS/,
	'short name stream dot');
unlike(http_get('/direct~1.::$index_allocation/file'), qr/SEE-THIS/,
	'short name dot stream');

# these should be mapped to /file

like(http_get('/file'), qr/X-Location: file/, 'file');
like(http_get('/file.'), qr/X-Location: file/, 'file dot');
like(http_get('/file..'), qr/X-Location: file/, 'file dot dot');
like(http_get('/file%20.%20.'), qr/X-Location: file/, 'file dots and spaces');
like(http_get('/file::$data..'), qr/X-Location: file|400 Bad/,
	'file stream dot dot');

###############################################################################
