#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for binary upgrade.

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

plan(skip_all => 'can leave orphaned process group')
	unless $ENV{TEST_NGINX_UNSAFE};

my $t = Test::Nginx->new(qr/http unix/)->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       unix:%%TESTDIR%%/unix.sock;
        server_name  localhost;
    }
}

EOF

my $d = $t->testdir();

$t->run();

###############################################################################

my $pid = $t->read_file('nginx.pid');
ok($pid, 'master pid');

kill 'USR2', $pid;

for (1 .. 30) {
	last if -e "$d/nginx.pid" && -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2
}

isnt($t->read_file('nginx.pid'), $pid, 'master pid changed');

kill 'QUIT', $pid;

for (1 .. 30) {
	last if ! -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2
}

ok(-e "$d/unix.sock", 'unix socket exists on old master shutdown');

# unix socket on new master termination

$pid = $t->read_file('nginx.pid');

kill 'USR2', $pid;

for (1 .. 30) {
	last if -e "$d/nginx.pid" && -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2
}

kill 'TERM', $t->read_file('nginx.pid');

for (1 .. 30) {
	last if ! -e "$d/nginx.pid.oldbin";
	select undef, undef, undef, 0.2
}

ok(-e "$d/unix.sock", 'unix socket exists on new master termination');

###############################################################################
