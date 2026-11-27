#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for graceful exit of old worker processes with EMFILE / EMSGSIZE
# on reading channel aux data.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_rlimit_nofile 32;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Pid $pid always;
        }
    }
}

EOF

$t->run();

###############################################################################

TODO: {
todo_skip 'long test', 2 unless $t->has_version('1.31.5')
	or $ENV{TEST_NGINX_UNSAFE};

local $TODO = 'not yet' unless $t->has_version('1.31.5');

my ($wpid) = http_get('/') =~ /X-Pid: (\d+)/;

my @s = map {  http("GET", start => 1) } 1 .. 24;

select undef, undef, undef, 0.2;

$t->reload();

select undef, undef, undef, 1.2;

map {  close $_ } @s;

select undef, undef, undef, 0.2;

$t->stop();

# recvmsg() errors are expected

$t->todo_alerts();

my $notice = `grep -F "[notice] $wpid" ${\($t->testdir())}/error.log`;
my $alerts = `grep -F '[alert]' ${\($t->testdir())}/error.log`;

like($notice, qr/gracefully shutting down/, 'old worker graceful shutdown');
unlike($alerts, qr/$wpid exited on signal 9/, 'old worker not killed');

}

###############################################################################
