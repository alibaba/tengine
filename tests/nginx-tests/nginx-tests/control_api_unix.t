#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for Control API over Unix domain sockets.

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

eval { require JSON::PP; };
plan(skip_all => "JSON::PP not installed") if $@;

eval { require IO::Socket::UNIX; };
plan(skip_all => 'IO::Socket::UNIX not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http rewrite control_api/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8080;
        server_name  localhost;

        location / {
            return 200 "foo";
        }
    }
}

EOF

my $path = $t->testdir() . '/ctrl.sock';

# Tengine uses -L for the control socket listen address: -l is already taken
# by T_NGX_SHOW_INFO to list all directives.
$t->args('-L', 'unix:' . $path)->run()->plan(6);

my $v = (sort { $a <=> $b } @{ api() })[-1];

###############################################################################

ok(-S $path, 'socket file created');
is((stat($path))[2] & 07777, 0600, 'socket permissions');
ok(api('/nginx')->{version}, 'nginx version');
like(http_patch('/control/config'), qr/200 OK/s, 'reload');

$t->stop();

ok(!-S $path, 'socket removed');

SKIP: {
skip 'unsafe', 1 unless $ENV{TEST_NGINX_UNSAFE};

my $testdir = $t->testdir();
my $dir = "$testdir/nowrite";
mkdir($dir);

IO::Socket::UNIX->new(Local => "$dir/stale.sock", Listen => 1);
chmod(0555, $dir);

# unlink fails (EACCES), bind fails (EADDRINUSE)

system("$Test::Nginx::NGINX "
	. "-p $testdir/ -c nginx.conf "
	. "-e error.log -L unix:$dir/stale.sock "
	. ">>$testdir/error.log 2>&1");

chmod(0755, $dir);

like($t->read_file('error.log'), qr/bind\(\) failed/,
	'bind fails with stale socket');
}

###############################################################################

sub api {
	my ($uri) = @_;

	$uri = defined $uri ? "/$v$uri" : '/';
	my $s = IO::Socket::UNIX->new(Peer => $path) or return;
	my ($body) = http_get($uri, socket => $s)
		=~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;

	return JSON::PP::decode_json($body);
}

sub http_patch {
	my ($url) = @_;

	my $s = IO::Socket::UNIX->new(Peer => $path) or return;
	return http(<<EOF, socket => $s);
PATCH /$v$url HTTP/1.0
Host: localhost

EOF
}

###############################################################################
