#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream least_time balancer module.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http stream stream_upstream_least_time/)
	->has(qw/proxy rewrite map/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    # separate upstreams for sane statistics

    upstream u {
        least_time last_byte;
        server 127.0.0.1:8081 fail_timeout=0;
        server 127.0.0.1:8082;
    }
    upstream u0 {
        least_time last_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u3 {
        least_time last_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u4 {
        least_time last_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u5 {
        least_time last_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u6 {
        least_time last_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u7 {
        least_time last_byte inflight;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream u8 {
        least_time first_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u9 {
        least_time first_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u10 {
        least_time first_byte;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream u11 {
        least_time connect;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  u0;
    }

    server {
        listen      127.0.0.1:8088;
        proxy_pass  u3;
    }

    server {
        listen      127.0.0.1:8089;
        proxy_pass  u4;
    }

    server {
        listen      127.0.0.1:8090;
        proxy_pass  u5;
    }

    server {
        listen      127.0.0.1:8091;
        proxy_pass  u6;
    }

    server {
        listen      127.0.0.1:8092;
        proxy_pass  u7;
    }

    server {
        listen      127.0.0.1:8093;
        proxy_pass  u8;
    }

    server {
        listen      127.0.0.1:8094;
        proxy_pass  u9;
    }

    server {
        listen      127.0.0.1:8095;
        proxy_pass  u10;
    }

    server {
        listen      127.0.0.1:8096;
        proxy_pass  u11;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $server_port:$arg_r $map_rate {
        %%PORT_8081%%:1    500;
        %%PORT_8082%%:2    500;
        ~both              500;

        default            0;
    }

    upstream u {
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        add_header X-Port $server_port;
        set $limit_rate $map_rate;

        location / { }
        location /backend {
            proxy_set_header X-Port $server_port;
            proxy_pass http://u;
        }
    }
}

EOF

$t->write_file('index.html', '0123456789' x 204);

$t->run_daemon(\&http_daemon, port(8083));
$t->run_daemon(\&http_daemon, port(8084));
$t->try_run('no least_time')->plan(13);

$t->waitforsocket('127.0.0.1:' . port(8083));
$t->waitforsocket('127.0.0.1:' . port(8084));

###############################################################################

my (@s);
my @ports = my ($p1, $p2, $p5, $p6, $p8, $p9, $p10, $p11, $p12, $p13, $p14,
	$p15, $p16) = (port(8081), port(8082), port(8085), port(8086),
	port(8088), port(8089), port(8090), port(8091), port(8092),
	port(8093), port(8094), port(8095), port(8096));

SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

# two peers with same last byte time and zero connections, expect round-robin

is(many('/', 10, "127.0.0.1:$p6"), "$p1: 5, $p2: 5", 'zero connections');

}

# if zero connections, backend with lesser average last byte time wins

is(many('/?r=1', 10, "127.0.0.1:$p5"), "$p1: 1, $p2: 9",
	'zero connections, last byte time');

# response time decay

# with response time ~4s+, a complete decay (i.e. below 20ms) takes 8s;
# with fail_timeout=0, yet more 4 seconds to wait until 1st probe request

sleep 2;

SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

is(many('/', 10, "127.0.0.1:$p5"), "$p2: 10", 'response time decay not yet');

}

sleep 2;
is(many('/', 10, "127.0.0.1:$p5"), "$p1: 1, $p2: 9",
	'response time decay probe');


# two peers with different last byte time
# verify that slower peer is not selected (both peers are alive)
# second backend with lesser last byte time wins

# prepare: generate some statistics for peer average last byte time
@s = map {
	http_get('/?r=1', start => 1, socket => getconn("127.0.0.1:$p8"))
} (1 .. 6);
http_end $_ for @s;

# verify that faster peer wins
is(many('/', 10, "127.0.0.1:$p8"), "$p2: 10", 'lesser last byte time');


# two peers with different last byte time
# verify that slower peer is not selected (both peers are alive)
# second backend has greater last byte time

@s = map {
	http_get('/?r=2', start => 1, socket => getconn("127.0.0.1:$p9"))
} (1 .. 6);
http_end $_ for @s;

is(many('/', 10, "127.0.0.1:$p9"), "$p1: 10", 'greater last byte time');


SKIP: {
skip 'unsafe on VM', 2 unless $ENV{TEST_NGINX_UNSAFE};

# no preference for same last byte time
# verify that peers are selected according to round-robin

map { http_get('/', socket => getconn("127.0.0.1:$p10")) } (1 .. 10);

is(many('/', 10, "127.0.0.1:$p10"), "$p1: 5, $p2: 5", 'equal last byte time');


# no preference for same last byte time, in average
# both peers generate fast AND slow answers, expect even selection

@s = map {
	http_get("/?r=$_", start => 1, socket => getconn("127.0.0.1:$p11"))
} (1, 2, 1, 2);
http_end $_ for @s;

like(parallel('/?r=both', 10, peer => "127.0.0.1:$p11"),
	qr/($p1|$p2): \d, ($p1|$p2): \d/, 'equal last byte time average');

}


SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

# lesser inflight time wins

# first backend starts hanging connections, thus rising inflight time
@s = map {
	http_get('/?r=1', start => 1, socket => getconn("127.0.0.1:$p12"))
} (1 .. 10);

select undef, undef, undef, 2.1;

# first backend with large inflight time doesn't get new connections
is(parallel('/?r=both', 8, delay => 0, peer => "127.0.0.1:$p12"), "$p2: 8",
	'inflight last byte time');

}


SKIP: {
skip 'unsafe on VM', 2 unless $ENV{TEST_NGINX_UNSAFE};

# first byte

# two peers with same first byte time and zero connections, expect round-robin

is(many('/', 10, "127.0.0.1:$p13"), "$p1: 5, $p2: 5",
	'zero connections first byte');

# two peers with same first byte time, diff. last byte time, expect round-robin

@s = map {
	http_get('/?r=1', start => 1, socket => getconn("127.0.0.1:$p14"))
} (1 .. 6);
http_end $_ for @s;

is(many('/', 10, "127.0.0.1:$p14"), "$p1: 5, $p2: 5", 'connections first byte');

}

# two peers with different first byte time
# second backend with lesser first byte time wins

@s = map {
	http_get('/backend?r=2', start => 1,
		socket => getconn("127.0.0.1:$p15"))
} (1 .. 2);
http_end $_ for @s;

is(many('/', 10, "127.0.0.1:$p15"), "$p2: 10", 'different first byte time');


SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

# two peers with same connect time and zero connections, expect round-robin

is(many('/', 10, "127.0.0.1:$p16"), "$p1: 5, $p2: 5",
	'zero connections connect time');

}

###############################################################################

sub getconn {
	my $peer = shift;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => $peer
	)
		or die "Can't connect to nginx: $!\n";

	return $s;
}

sub many {
	my ($uri, $count, $peer) = @_;
	my %ports;

	for (1 .. $count) {
		if (http_get($uri, socket => getconn($peer)) =~ /X-Port: (\d+)/)
		{
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}

		select undef, undef, undef, 0.04;
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub parallel {
	my ($uri, $count, %opts) = @_;
	my (@sockets, %ports);
	my $delay = defined $opts{delay} ? $opts{delay} : 0.4;
	my $peer = $opts{peer};

	for (1 .. $count) {
		push(@sockets,
			http_get($uri, start => 1, socket => getconn($peer)));
		select undef, undef, undef, $delay if $delay;
	}

	for (1 .. $count) {
		if (http_end(pop(@sockets)) =~ /X-Port: (\d+)/) {
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
		my $xport = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
		next if $uri eq '';
		$xport = $1 if $headers =~ /X-Port: (\d+)/;

		# first byte delay

		if ($xport == port(8081)) {
			sleep 1;
		}

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

EOF

		if ($xport == port(8082)) {
			print $client 'y' x 4096;
		}
	}
}

###############################################################################
