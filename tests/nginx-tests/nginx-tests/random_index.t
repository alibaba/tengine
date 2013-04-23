#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for random index module.

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

plan(skip_all => 'no symlinks on win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http random_index/)->plan(1)
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
            random_index on;
        }
    }
}

EOF

my $d = $t->testdir();

mkdir("$d/x");
mkdir("$d/x/test-dir");
symlink("$d/x/test-dir", "$d/x/test-dir-link");

$t->write_file('test-file', 'RIGHT');
symlink("$d/test-file", "$d/x/test-file-link");

$t->run();

###############################################################################

like(http_get('/x/'), qr/RIGHT/s, 'file');

###############################################################################
