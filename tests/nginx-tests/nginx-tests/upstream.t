#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for upstream module and balancers.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081 max_fails=3 fail_timeout=10s;
        server 127.0.0.1:8082 max_fails=3 fail_timeout=10s;
    }

    upstream u2 {
        server 127.0.0.1:8081 max_fails=3 fail_timeout=10s;
        server 127.0.0.1:8082 max_fails=3 fail_timeout=10s;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }
        location /close2 {
            proxy_pass http://u2;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->run_daemon(\&http_daemon, port(8082));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

my @ports = my ($p1, $p2) = (port(8081), port(8082));

is(many('/', 30), "$p1: 15, $p2: 15", 'balanced');

# from 9 first requests to the first port, only 6 will be successful,
# 3rd, 6th, and 9th requests will fail; after this the backend
# will be considered down and won't be used till fail_timeout passes

is(many('/close', 30), "$p1: 6, $p2: 24", 'failures');

SKIP: {
skip 'long test', 1 unless $ENV{TEST_NGINX_UNSAFE};

# bug: failures counter is reset if first request in a second succeeds
#
# delay added to make sure first 9 requests will take more than 1s;
# note that the test is racy and may unexpectedly succeed

is(many('/close2', 30, delay => 0.2), "$p1: 6, $p2: 24", 'failures delay');

}

###############################################################################

sub many {
	my ($uri, $count, %opts) = @_;
	my %ports;

	for (1 .. $count) {
		if (http_get($uri) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}

		select undef, undef, undef, $opts{delay} if $opts{delay};
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub http_daemon {
	my ($port) = @_;
	my $count = 1;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri =~ 'close' && $port == port(8081) && $count++ % 3 == 0)
		{
			next;
		}

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Port: $port

OK
EOF

		close $client;
	}
}

###############################################################################
