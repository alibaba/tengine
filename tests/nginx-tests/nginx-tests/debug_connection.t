#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for debug_connection.

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

my $t = Test::Nginx->new()->has(qw/http --with-debug ipv6 proxy/);

plan(skip_all => 'not yet') unless $t->has_version('1.5.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
    debug_connection ::1;
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_log %%TESTDIR%%/debug1.log alert;
    error_log %%TESTDIR%%/debug2.log alert;

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:8080;
        server_name  localhost;

        location /debug {
            proxy_pass http://[::1]:8080/;
        }
    }
}

EOF

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no inet6 support') if $@;

$t->plan(5);

###############################################################################

my $d = $t->testdir();

http_get('/');
is(read_file("$d/debug1.log"), '', 'no debug_connection file 1');
is(read_file("$d/debug2.log"), '', 'no debug_connection file 1');

http_get('/debug');
like(read_file("$d/debug1.log"), qr/\[debug\]/, 'debug_connection file 1');
like(read_file("$d/debug2.log"), qr/\[debug\]/, 'debug_connection file 2');
is(read_file("$d/debug1.log"), read_file("$d/debug2.log"),
	'debug_connection file1 file2 match');

###############################################################################

sub read_file {
	my ($file) = shift;
	open my $fh, '<', $file or return "$!";
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

###############################################################################
