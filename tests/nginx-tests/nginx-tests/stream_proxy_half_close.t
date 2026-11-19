#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy_half_close directive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8081;

        proxy_half_close  on;
    }
}

EOF

$t->run()->plan(2);

###############################################################################

my ($s, $u) = pair(8080, 8081);
shutdown($u, 1);
is(proxy($s, $u, 'SEE'), 'SEE', 'half close upstream');

($s, $u) = pair(8080, 8081);
shutdown($s, 1);
is(proxy($u, $s, 'SEE'), 'SEE', 'half close client');

###############################################################################

sub pair {
	my ($server, $backend) = @_;

	my $listen = IO::Socket::INET->new(
		LocalHost => '127.0.0.1:' . port($backend),
		Listen => 5,
		Reuse => 1,
	)
		or die "Can't listen on $server: $!\n";

	my $connect = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerHost => '127.0.0.1:' . port($server),
	)
		or die "Can't connect to $server: $!\n";

	my $accept = $listen->accept() if IO::Select->new($listen)->can_read(3);

	return $connect, $accept;
}

sub proxy {
	my ($from, $to, $msg) = @_;
	proxy_from($from, $msg);
	return proxy_to($to);
}

sub proxy_from {
	my ($s, $msg) = @_;

	local $SIG{PIPE} = 'IGNORE';

	while (IO::Select->new($s)->can_write(5)) {
		my $n = $s->syswrite($msg);
		log_out(substr($msg, 0, $n));
		last unless $n;

		$msg = substr($msg, $n);
		last unless length $msg;
	}
}

sub proxy_to {
	my ($s) = @_;
	my $buf;

	$s->sysread($buf, 1024) if IO::Select->new($s)->can_read(5);

	log_in($buf);
	return $buf;
}

###############################################################################
