#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream random balancer module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_upstream_zone stream_upstream_random/)->plan(12)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 2;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u {
        zone z 1m;
        random;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream lc {
        zone lc 1m;
        random two;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream w {
        zone w 1m;
        random two least_conn;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082 weight=2;
    }

    upstream mc {
        zone mc 1m;
        random;
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 max_conns=1;
    }

    upstream mc2 {
        zone mc 1m;
        random two;
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 max_conns=1;
    }

    upstream one {
        random;
        server 127.0.0.1:8081;
    }

    upstream two {
        random two;
        server 127.0.0.1:8081;
    }

    upstream zone {
        zone z 1m;
        random;
        server 127.0.0.1:8081;
    }

    upstream ztwo {
        zone z 1m;
        random two;
        server 127.0.0.1:8081;
    }

    upstream fail {
        zone fail 1m;
        random;
        server 127.0.0.1:8096;
        server 127.0.0.1:8083 down;
        server 127.0.0.1:8082;
    }

    upstream fail2 {
        zone fail2 1m;
        random two;
        server 127.0.0.1:8096;
        server 127.0.0.1:8083 down;
        server 127.0.0.1:8082;
    }

    proxy_connect_timeout 2;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  lc;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  w;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  mc;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  mc2;
    }

    server {
        listen      127.0.0.1:8087;
        proxy_pass  one;
    }

    server {
        listen      127.0.0.1:8088;
        proxy_pass  two;
    }

    server {
        listen      127.0.0.1:8089;
        proxy_pass  zone;
    }

    server {
        listen      127.0.0.1:8090;
        proxy_pass  ztwo;
    }

    server {
        listen      127.0.0.1:8091;
        proxy_pass  fail;
    }

    server {
        listen      127.0.0.1:8092;
        proxy_pass  fail2;
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->run_daemon(\&http_daemon, port(8082));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

my @ports = my ($port1, $port2) = (port(8081), port(8082));

like(get(8080, '/'), qr/X-Port: ($port1|$port2)/, 'random');
like(get(8083, '/'), qr/X-Port: ($port1|$port2)/, 'random two');

my $s = get(8083, '/w', start => 1, sleep => 0.5);
my $r = get(8083, '/');
my ($p) = http_end($s) =~ /X-Port: (\d+)/;
like($r, qr/X-Port: (?!$p)/, 'random wait');

SKIP: {
skip 'long test', 3 unless $ENV{TEST_NGINX_UNSAFE};

is(parallel(8084, '/w', 3), "$port1: 1, $port2: 2", 'random weight');

is(parallel(8085, '/w', 4), "$port1: 2, $port2: 1", 'max_conns');
is(parallel(8086, '/w', 4), "$port1: 2, $port2: 1", 'max_conns two');

}

# single variants

like(get(8087, '/'), qr/X-Port: $port1/, 'single one');
like(get(8088, '/'), qr/X-Port: $port1/, 'single two');
like(get(8089, '/'), qr/X-Port: $port1/, 'zone one');
like(get(8090, '/'), qr/X-Port: $port1/, 'zone two');

like(many(8091, '/', 10), qr/$port2: 10/, 'failures');
like(many(8092, '/', 10), qr/$port2: 10/, 'failures two');

###############################################################################

sub get {
	my ($port, $uri, %opts) = @_;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1',
		PeerPort => port($port),
	)
		or die "Can't connect to nginx: $!\n";

	http_get($uri, socket => $s, %opts);
}

sub many {
	my ($port, $uri, $count, %opts) = @_;
	my %ports;

	for (1 .. $count) {
		if (get($port, $uri) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}

		select undef, undef, undef, $opts{delay} if $opts{delay};
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub parallel {
	my ($port, $uri, $n) = @_;
	my %ports;

	my @s = map { get($port, $uri, start => 1, sleep => 0.1) } (1 .. $n);

	for (@s) {
		my $r = http_end($_);
		if ($r && $r =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub http_daemon {
	my ($port) = @_;

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

		if ($uri eq '/w') {
			Test::Nginx::log_core('||', "$port: sleep(2.5)");
			select undef, undef, undef, 2.5;
		}

		if ($uri eq '/close' && $port == port(8081)) {
			next;
		}

		Test::Nginx::log_core('||', "$port: response, 200");
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
