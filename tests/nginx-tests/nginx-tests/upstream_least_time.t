#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream least_time balancer module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()
	->has(qw/http proxy upstream_least_time rewrite map/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

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
        least_time header;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u9 {
        least_time header;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }
    upstream u10 {
        least_time header;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    map $server_port:$arg_r $map_rate {
        %%PORT_8081%%:1    500;
        %%PORT_8082%%:2    500;
        ~both              500;

        default            0;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /u/ {
            proxy_pass http://u/;
        }
        location /u0/ {
            proxy_pass http://u0/;
        }
        location /u3/ {
            proxy_pass http://u3/;
        }
        location /u4/ {
            proxy_pass http://u4/;
        }
        location /u5/ {
            proxy_pass http://u5/;
        }
        location /u6/ {
            proxy_pass http://u6/;
        }
        location /u7/ {
            proxy_pass http://u7/;
        }
        location /u8/ {
            proxy_pass http://u8/;
        }
        location /u9/ {
            proxy_pass http://u9/;
        }
        location /u10/ {
            proxy_pass http://u10/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        keepalive_requests 1;

        location / {
            add_header X-Port $server_port;
            set $limit_rate $map_rate;
        }

        location /headers {
            add_header X-Port $server_port;
            proxy_set_header X-Port $server_port;
            set $limit_rate $map_rate;
            proxy_pass http://127.0.0.1:8083;
        }
    }
}

EOF

$t->write_file('index.html', '0123456789' x 204);

$t->run_daemon(\&http_daemon, port(8083));
$t->try_run('no least_time')->plan(12);

$t->waitforsocket('127.0.0.1:' . port(8083));

###############################################################################

my (@s);
my @ports = my ($p1, $p2) = (port(8081), port(8082));

SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

# two peers with same response time and zero connections, expect round-robin

is(many('/u0/', 10), "$p1: 5, $p2: 5", 'zero connections');

}

# if zero connections, backend with lesser average response time wins

is(many('/u/?r=1', 10), "$p1: 1, $p2: 9", 'zero connections, response time');

# response time decay

# with response time ~4s+, a complete decay (i.e. below 20ms) takes 8s;
# with fail_timeout=0, yet more 4 seconds to wait until 1st probe request

sleep 2;

SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

is(many('/u/', 10), "$p2: 10", 'response time decay not yet');

}

sleep 2;
is(many('/u/', 10), "$p1: 1, $p2: 9", 'response time decay probe');


# two peers with different response time
# verify that slower peer is not selected (both peers are alive)
# second backend with lesser response time wins

# prepare: generate some statistics for peer average response time
@s = map { http_get('/u3/?r=1', start => 1) } (1 .. 6);
http_end $_ for @s;

# verify that faster peer wins
is(many('/u3/', 10), "$p2: 10", 'lesser response time');


# two peers with different response time
# verify that slower peer is not selected (both peers are alive)
# second backend has greater response time

@s = map { http_get('/u4/?r=2', start => 1) } (1 .. 6);
http_end $_ for @s;

is(many('/u4/', 10), "$p1: 10", 'greater response time');


SKIP: {
skip 'unsafe on VM', 2 unless $ENV{TEST_NGINX_UNSAFE};

# no preference for same response time
# verify that peers are selected according to round-robin

map { http_get('/u5/') } (1 .. 10);

is(many('/u5/', 10), "$p1: 5, $p2: 5", 'equal response time');


# no preference for same response time, in average
# both peers generate fast AND slow answers, expect even selection

@s = map { http_get("/u6/?r=$_", start => 1) } (1, 2, 1, 2);
http_end $_ for @s;

like(parallel('/u6/?r=both', 10), qr/($p1|$p2): \d, ($p1|$p2): \d/,
	'equal response time average');

}


SKIP: {
skip 'unsafe on VM', 1 unless $ENV{TEST_NGINX_UNSAFE};

# lesser inflight time wins

# first backend starts hanging connections, thus rising inflight time
@s = map { http_get('/u7/?r=1', start => 1) } (1 .. 10);

select undef, undef, undef, 2.1;

# first backend with large inflight time doesn't get new connections
is(parallel('/u7/?r=both', 8, delay => 0), "$p2: 8", 'inflight response time');

}


SKIP: {
skip 'unsafe on VM', 2 unless $ENV{TEST_NGINX_UNSAFE};

# response header

# two peers with same header time and zero connections, expect round-robin

is(many('/u8/', 10), "$p1: 5, $p2: 5", 'zero connections header');

# two peers with same header time, different response time, expect round-robin

@s = map { http_get('/u9/?r=1', start => 1) } (1 .. 6);
http_end $_ for @s;

is(many('/u9/', 10), "$p1: 5, $p2: 5", 'connections header');

}

# two peers with different header time
# second backend with lesser header time wins

@s = map { http_get('/u10/headers?r=both', start => 1) } (1 .. 6);
http_end $_ for @s;

is(many('/u10/headers', 10), "$p2: 10", 'different header time');

###############################################################################

sub many {
	my ($uri, $count) = @_;
	my %ports;

	for (1 .. $count) {
		if (http_get($uri) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub parallel {
	my ($uri, $count, %opts) = @_;
	my (@sockets, %ports);
	my $delay = defined $opts{delay} ? $opts{delay} : 0.4;

	for (1 .. $count) {
		push(@sockets, http_get($uri, start => 1));
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

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
EOF

		if ($xport == port(8081)) {
			print $client 'X-Header: ' . 'x' x 2048 . CRLF;
		}

		print $client CRLF;

		if ($xport == port(8082)) {
			print $client 'y' x 4096;
		}
	}
}

###############################################################################
