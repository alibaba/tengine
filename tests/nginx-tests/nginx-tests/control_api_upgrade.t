#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for Control API over Unix domain sockets during binary upgrade.

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

plan(skip_all => 'can leave orphaned process group')
	unless $ENV{TEST_NGINX_UNSAFE};

eval { require IO::Socket::UNIX; };
plan(skip_all => 'IO::Socket::UNIX not installed') if $@;

my $t = Test::Nginx->new()->has(qw/control_api/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8080;
        server_name  localhost;
    }
}

EOF

my $d = $t->testdir();
my $path = "$d/ctrl.sock";

# Tengine uses -L for the control socket listen address: -l is already taken
# by T_NGX_SHOW_INFO to list all directives.
$t->args('-L', 'unix:' . $path)->run()->plan(8);

my $v = (sort { $a <=> $b } @{ api() })[-1];

###############################################################################

ok(api('/nginx')->{version}, 'api before upgrade');

my $pid = $t->read_file('nginx.pid');

# binary upgrade

kill 'USR2', $pid;

for (1 .. 30) {
	last if -e "$d/nginx.pid" && -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2;
}

isnt($t->read_file('nginx.pid'), $pid, 'master pid changed');
ok(-S $path, 'socket exists after upgrade');
ok(api('/nginx')->{version}, 'api after upgrade');

# graceful shutdown of old master

kill 'QUIT', $pid;

for (1 .. 30) {
	last if ! -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2;
}

ok(-S $path, 'socket on old master shutdown');
ok(api('/nginx')->{version}, 'api on old master shutdown');

# second upgarade cyrcle: new master termination (rollback)

$pid = $t->read_file('nginx.pid');

kill 'USR2', $pid;

for (1 .. 30) {
	last if -e "$d/nginx.pid" && -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2;
}

kill 'TERM', $t->read_file('nginx.pid');

for (1 .. 30) {
	last if ! -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2;
}

ok(-S $path, 'socket on new master termination');
ok(api('/nginx')->{version}, 'api on new master termination');

###############################################################################

sub api {
	my ($uri) = @_;

	$uri = defined $uri ? "/$v$uri" : '/';
	my $s = IO::Socket::UNIX->new(Peer => $path) or return;
	my ($body) = http_get($uri, socket => $s)
		=~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;

	return JSON::PP::decode_json($body);
}

###############################################################################
