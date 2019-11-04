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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone upstream_random/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 2;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        zone z 1m;
        random;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 down;
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

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }

        location /lc/ {
            proxy_pass http://lc/;
        }

        location /w {
            proxy_pass http://w;
        }

        location /mc/ {
            proxy_pass http://mc/;
        }

        location /mc2/ {
            proxy_pass http://mc2/;
        }

        location /one {
            proxy_pass http://one;
        }

        location /two {
            proxy_pass http://two;
        }

        location /zone {
            proxy_pass http://zone;
        }

        location /ztwo {
            proxy_pass http://ztwo;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->run_daemon(\&http_daemon, port(8082));
$t->try_run('no upstream random')->plan(12);

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

my @ports = my ($port1, $port2) = (port(8081), port(8082));

like(http_get('/'), qr/X-Port: ($port1|$port2)/, 'random');
like(http_get('/lc/'), qr/X-Port: ($port1|$port2)/, 'random two');

my $s = http_get('/lc/w', start => 1, sleep => 0.5);
my $r = http_get('/lc/');
my ($p) = http_end($s) =~ /X-Port: (\d+)/;
like($r, qr/X-Port: (?!$p)/, 'random wait');

SKIP: {
skip 'long test', 3 unless $ENV{TEST_NGINX_UNSAFE};

is(parallel('/w', 3), "$port1: 1, $port2: 2", 'random weight');

is(parallel('/mc/w', 4), "$port1: 2, $port2: 1", 'max_conns');
is(parallel('/mc2/w', 4), "$port1: 2, $port2: 1", 'max_conns two');

}

# single variants

like(http_get('/one'), qr/X-Port: $port1/, 'single one');
like(http_get('/two'), qr/X-Port: $port1/, 'single two');
like(http_get('/zone'), qr/X-Port: $port1/, 'zone one');
like(http_get('/ztwo'), qr/X-Port: $port1/, 'zone two');

like(many('/close', 10), qr/$port2: 10/, 'failures');
like(many('/lc/close', 10), qr/$port2: 10/, 'failures two');

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

sub parallel {
	my ($uri, $n) = @_;
	my %ports;

	my @s = map { http_get($uri, start => 1, sleep => 0.1) } (1 .. $n);

	for (@s) {
		if (http_end($_) =~ /X-Port: (\d+)/) {
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
