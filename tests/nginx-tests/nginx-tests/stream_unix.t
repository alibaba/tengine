#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Simple tests for stream with unix socket.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Socket::UNIX; };
plan(skip_all => 'IO::Socket::UNIX not installed') if $@;

my $t = Test::Nginx->new()->has(qw/stream unix/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u {
        server unix:%%TESTDIR%%/unix.sock;
    }

    server {
        listen       127.0.0.1:8080;
        proxy_pass   unix:%%TESTDIR%%/unix.sock;
    }

    server {
        listen       127.0.0.1:8081;
        proxy_pass   u;
    }
}

EOF

my $path = $t->testdir() . '/unix.sock';

$t->run_daemon(\&stream_daemon, $path);
$t->run();

# wait for unix socket to appear

for (1 .. 50) {
	last if -S $path;
	select undef, undef, undef, 0.1;
}

###############################################################################

my $str = 'SEE-THIS';

is(stream('127.0.0.1:' . port(8080))->io($str), $str, 'proxy');
is(stream('127.0.0.1:' . port(8081))->io($str), $str, 'upstream');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::UNIX->new(
		Proto => 'tcp',
		Local => shift,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		log2c("(new connection $client)");

		$client->sysread(my $buffer, 65536) or next;

		log2i("$client $buffer");

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
