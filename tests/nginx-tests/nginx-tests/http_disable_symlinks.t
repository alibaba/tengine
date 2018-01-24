#!/usr/bin/perl

# (C) Andrey Belov

# Tests for disable_symlinks directive.

###############################################################################

use warnings;
use strict;

use Test::More;
use POSIX;
use Cwd qw/ realpath /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite symlink/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  s1;

        location /on/ {
            disable_symlinks on;
        }

        location /not_owner/ {
            disable_symlinks if_not_owner;
        }

        location /try_on/ {
            disable_symlinks on;
            try_files $uri $uri.html =404;
        }

        location /try_not_owner/ {
            disable_symlinks if_not_owner;
            try_files $uri $uri.txt =404;
        }

        location /if_on/ {
            disable_symlinks on;
            if (-f $request_filename) {
                return 204;
            }
        }

        location /if_not_owner/ {
            disable_symlinks if_not_owner;
            if (-f $request_filename) {
                return 204;
            }
        }

        location /complex/1/ {
            disable_symlinks on;
            alias %%TESTDIR%%/./cached/../;
        }

        location /complex/2/ {
            disable_symlinks on;
            alias %%TESTDIR%%//./cached/..//;
        }

        location /complex/3/ {
            disable_symlinks on;
            alias ///%%TESTDIR%%//./cached/..//;
        }

        location ~ (.+/)tail$ {
            disable_symlinks on;
            alias %%TESTDIR%%/$1;
        }

        location ~ (.+/)tailowner$ {
            disable_symlinks if_not_owner;
            alias %%TESTDIR%%/$1;
        }

        location ~ (.+/)tailoff$ {
            disable_symlinks off;
            alias %%TESTDIR%%/$1;
        }

        location /dir {
            disable_symlinks on;
            try_files $uri/ =404;
        }

        location /from {
            disable_symlinks on from=$document_root;

            location /from/wo_slash {
                alias %%TESTDIR%%/dirlink;
            }
            location /from/with_slash/ {
                alias %%TESTDIR%%/dirlink/;
            }
            location ~ ^/from/exact/(.+)$ {
                alias %%TESTDIR%%/$1;
            }
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  s2;

        open_file_cache max=16 inactive=60s;
        open_file_cache_valid 30s;
        open_file_cache_min_uses 1;
        open_file_cache_errors on;

        location /cached-off/ {
            disable_symlinks off;
            alias %%TESTDIR%%/cached/;
        }

        location /cached-on/ {
            disable_symlinks on;
            alias %%TESTDIR%%/cached/;
        }

        location /cached-if-not-owner/ {
            disable_symlinks if_not_owner;
            alias %%TESTDIR%%/cached/;
        }

        location / {
            disable_symlinks off;
        }
    }
}

EOF

my $uid = getuid();
my ($extfile) = grep { -f "$_" && $uid != (stat($_))[4] }
	('/etc/resolv.conf', '/etc/protocols', '/etc/host.conf');

plan(skip_all => 'no external file found')
	if !defined $extfile;

$t->try_run('no disable_symlinks')->plan(28);

my $d = $t->testdir();

mkdir("$d/on");
mkdir("$d/not_owner");
mkdir("$d/try_on");
mkdir("$d/try_not_owner");
mkdir("$d/if_on");
mkdir("$d/if_not_owner");
mkdir("$d/cached");

$t->write_file("empty.html", "");
symlink("empty.html", "$d/link");
symlink($extfile, "$d/link2");

$t->write_file("on/empty.html", "");
symlink("empty.html", "$d/on/link");
symlink($extfile, "$d/on/link2");

$t->write_file("not_owner/empty.html", "");
symlink("empty.html", "$d/not_owner/link");
symlink($extfile, "$d/not_owner/link2");

$t->write_file("try_on/try.html", "LOCAL TRY");
symlink($extfile, "$d/try_on/try");

$t->write_file("try_not_owner/try.html", "LOCAL TRY");
symlink($extfile, "$d/try_not_owner/try");
symlink("try.html", "$d/try_not_owner/try.txt");

$t->write_file("if_on/empty.html", "");
symlink("empty.html", "$d/if_on/link");
symlink($extfile, "$d/if_on/link2");

$t->write_file("if_not_owner/empty.html", "");
symlink("empty.html", "$d/if_not_owner/link");
symlink($extfile, "$d/if_not_owner/link2");

mkdir("$d/dir");
$t->write_file("dir/empty.html", "");
symlink("dir", "$d/dirlink");

symlink($extfile, "$d/cached/link");

###############################################################################

SKIP: {
skip 'cannot test under symlink', 25 if $d ne realpath($d);

like(http_get_host('s1', '/link'), qr!200 OK!, 'static (off, same uid)');
like(http_get_host('s1', '/link2'), qr!200 OK!, 'static (off, other uid)');

like(http_get_host('s1', '/on/link'), qr!403 Forbidden!,
	'static (on, same uid)');
like(http_get_host('s1', '/on/link2'), qr!403 Forbidden!,
	'static (on, other uid)');

like(http_get_host('s1', '/not_owner/link'), qr!200 OK!,
	'static (if_not_owner, same uid)');
like(http_get_host('s1', '/not_owner/link2'), qr!403 Forbidden!,
	'static (if_not_owner, other uid)');

like(http_get_host('s1', '/try_on/try'), qr/LOCAL TRY/,
	'try_files (on)');
like(http_get_host('s1', '/try_not_owner/try'), qr/LOCAL TRY/,
	'try_files (if_not_owner)');

like(http_get_host('s1', '/if_on/link'), qr!403 Forbidden!,
	'if (on, same uid)');
like(http_get_host('s1', '/if_on/link2'), qr!403 Forbidden!,
	'if (on, other uid)');

like(http_get_host('s1', '/if_not_owner/link'), qr!204 No Content!,
	'if (if_not_owner, same uid)');
like(http_get_host('s1', '/if_not_owner/link2'), qr!403 Forbidden!,
	'if (if_not_owner, other uid)');

like(http_get_host('s2', '/cached-off/link'), qr!200 OK!,
	'open_file_cache (pass 1)');
like(http_get_host('s2', '/cached-on/link'), qr!403 Forbidden!,
	'open_file_cache (pass 2)');
like(http_get_host('s2', '/cached-off/link'), qr!200 OK!,
	'open_file_cache (pass 3)');
like(http_get_host('s2', '/cached-if-not-owner/link'), qr!403 Forbidden!,
	'open_file_cache (pass 4)');
like(http_get_host('s2', '/cached-off/link'), qr!200 OK!,
	'open_file_cache (pass 5)');

like(http_get('/complex/1/empty.html'), qr!200 OK!, 'complex root 1');
like(http_get('/complex/2/empty.html'), qr!200 OK!, 'complex root 2');
like(http_get('/complex/3/empty.html'), qr!200 OK!, 'complex root 3');

# workaround for freebsd 8: we use O_EXEC instead of O_SEARCH (since there
# is no O_SEARCH), and O_DIRECTORY does nothing.  setting the 'x' bit
# tests to pass as openat() will correctly fail with ENOTDIR

chmod(0700, "$d/link");
my $rc = $^O eq 'darwin' ? 200 : 404;

like(http_get('/link/tail'), qr!40[34] !, 'file with trailing /, on');
like(http_get('/link/tailowner'), qr!404 !, 'file with trailing /, owner');
like(http_get('/link/tailoff'), qr!$rc !, 'file with trailing /, off');

like(http_get('/dirlink'), qr!404 !, 'directory without /');
like(http_get('/dirlink/'), qr!404 !, 'directory with trailing /');

} # SKIP: cannot test under symlink

like(http_get('/from/wo_slash/empty.html'), qr!200 OK!, '"from=" without /');
like(http_get('/from/with_slash/empty.html'), qr!200 OK!, '"from=" with /');
like(http_get('/from/exact/link'), qr!200 OK!, '"from=" exact match');

###############################################################################

sub http_get_host {
	my ($host, $url) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: $host

EOF
}

###############################################################################
