#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for debug_connection with unix socket.

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

my $t = Test::Nginx->new()->has(qw/http --with-debug unix proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
    debug_connection unix:;
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_log %%TESTDIR%%/debug1.log alert;
    error_log %%TESTDIR%%/debug2.log alert;

    server {
        listen       127.0.0.1:8080;
        listen       unix:%%TESTDIR%%/unix.sock;
        server_name  localhost;

        location /debug {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock:/;
        }
    }
}

EOF

$t->run()->plan(5);

###############################################################################

http_get('/');

select undef, undef, undef, 0.1;
is($t->read_file('debug1.log'), '', 'no debug_connection file 1');
is($t->read_file('debug2.log'), '', 'no debug_connection file 2');

http_get('/debug');

select undef, undef, undef, 0.1;
like($t->read_file('debug1.log'), qr/\[debug\]/, 'debug_connection file 1');
like($t->read_file('debug2.log'), qr/\[debug\]/, 'debug_connection file 2');
is($t->read_file('debug1.log'), $t->read_file('debug2.log'),
	'debug_connection file1 file2 match');

###############################################################################
