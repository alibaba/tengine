#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for ngx_http_upstream_check_module with random, random two, and
# consistent hash upstream balancers.
#
# Each unhealthy peer still listens and serves HTTP 200 on "/" while failing
# the active health check on "/health" (HTTP 500), and proxy_next_upstream is
# turned off with max_fails=0.  That isolates active health checks from passive
# failover: without ngx_http_upstream_check_peer_down() in the balancer,
# requests keep landing on the check-down peer and still receive HTTP 200.
#
# For consistent hash, peer 8083 starts healthy so we can record one key that
# hashes to 8083 and another that hashes to a healthy peer, then flip 8083's
# /health to 500 and verify that the first key moves to a single healthy peer
# while the second keeps its original mapping (ruling out a fallback to round
# robin).

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_hash
	upstream_random ngx_http_upstream_check_module/)->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_random {
        random;
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8082 max_fails=0;
        server 127.0.0.1:8083 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    # Three peers (two healthy, one check-down) keep "random two" on its main
    # selection path instead of exhausting tries and falling back to round robin.
    upstream u_random2 {
        random two;
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8082 max_fails=0;
        server 127.0.0.1:8083 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream u_chash {
        hash $arg_a consistent;
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8082 max_fails=0;
        server 127.0.0.1:8083 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream u_random_down {
        random;
        server 127.0.0.1:8083 max_fails=0;
        server 127.0.0.1:8084 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream u_random2_down {
        random two;
        server 127.0.0.1:8083 max_fails=0;
        server 127.0.0.1:8084 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream u_chash_down {
        hash $arg_a consistent;
        server 127.0.0.1:8083 max_fails=0;
        server 127.0.0.1:8084 max_fails=0;

        check interval=200 rise=1 fall=1 timeout=1000 default_down=false type=http;
        check_http_send "GET /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_next_upstream off;

        location = /status {
            check_status csv;
        }

        location /random {
            proxy_pass http://u_random;
        }

        location /random2 {
            proxy_pass http://u_random2;
        }

        location /chash {
            proxy_pass http://u_chash;
        }

        location /random_down {
            proxy_pass http://u_random_down;
        }

        location /random2_down {
            proxy_pass http://u_random2_down;
        }

        location /chash_down {
            proxy_pass http://u_chash_down;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        location = /health {
            return 200 "ok\n";
        }

        location / {
            add_header X-Port $server_port;
            return 200 "ok\n";
        }
    }

    server {
        listen       127.0.0.1:8083;
        server_name  localhost;

        location = /health {
            if (-f %%TESTDIR%%/p3_down) {
                return 500 "fail\n";
            }
            return 200 "ok\n";
        }

        location / {
            add_header X-Port $server_port;
            return 200 "ok\n";
        }
    }

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;

        location = /health {
            return 500 "fail\n";
        }

        location / {
            add_header X-Port $server_port;
            return 200 "ok\n";
        }
    }
}

EOF

$t->run();

###############################################################################

my ($p1, $p2, $p3, $p4) = (port(8081), port(8082), port(8083), port(8084));

# Phase 1: 8081, 8082 and 8083 are healthy (12 up peers across the six
# upstreams); 8084 is down (3 down peers).

my ($converged, $last_status) = wait_status(
	qr/^[^,]+,[^,]+,127\.0\.0\.1:(?:$p1|$p2|$p3),up,[1-9]/m, 12,
	qr/^[^,]+,[^,]+,127\.0\.0\.1:$p4,down,0,[1-9]/m, 3,
);

ok($converged, 'initial health check converged with p3 up')
	or diag("last /status:\n" . (defined $last_status ? $last_status : '<undef>'));

SKIP: {
	skip 'initial health check did not converge', 13 unless $converged;

	my ($key_p3, $key_healthy, $healthy_port);
	for my $i (1 .. 100) {
		my $port = chash_port($i);
		next unless defined $port;

		if (!defined $key_p3 && $port == $p3) {
			$key_p3 = $i;
		} elsif (!defined $key_healthy && ($port == $p1 || $port == $p2)) {
			$key_healthy = $i;
			$healthy_port = $port;
		}

		last if defined $key_p3 && defined $key_healthy;
	}

	my $found_keys = defined $key_p3 && defined $key_healthy;
	ok($found_keys, 'chash: found keys mapping to p3 and a healthy peer before failure');

	# Phase 2: fail 8083's /health probe and wait until all six upstreams
	# reflect 6 up peers (8081/8082) and 9 down peers (8083/8084).

	$t->write_file('p3_down', "1\n");

	($converged, $last_status) = wait_status(
		qr/^[^,]+,[^,]+,127\.0\.0\.1:(?:$p1|$p2),up,[1-9]/m, 6,
		qr/^[^,]+,[^,]+,127\.0\.0\.1:(?:$p3|$p4),down,0,[1-9]/m, 9,
	);

	ok($converged, 'health check marked p3 down after probe failure')
		or diag("last /status:\n" . (defined $last_status ? $last_status : '<undef>'));

	SKIP: {
		skip 'health check did not converge after p3 failure', 11
			unless $converged;

		SKIP: {
			skip 'pre-failure chash keys not found', 2
				unless $found_keys;

			my ($failover_port, $failover_ok) = (undef, 0);
			for (1 .. 5) {
				my $port = chash_port($key_p3);
				if (defined $port && ($port == $p1 || $port == $p2)) {
					$failover_port = $port unless defined $failover_port;
					$failover_ok++ if $port == $failover_port;
				}
			}

			is($failover_ok, 5,
				'chash: key from down peer consistently fails over to a healthy peer');

			my $stable_ok = 0;
			for (1 .. 5) {
				my $port = chash_port($key_healthy);
				$stable_ok++ if defined $port && $port == $healthy_port;
			}

			is($stable_ok, 5,
				'chash: key on healthy peer preserves mapping after p3 goes down');
		}

		my ($ok, $down_hits);

		($ok, $down_hits) = probe('/random', 40, 0);
		is($ok, 40, 'random: all requests routed to healthy peers');
		is($down_hits, 0, 'random: no request routed to check-down peer');

		($ok, $down_hits) = probe('/random2', 40, 0);
		is($ok, 40, 'random two: all requests routed to healthy peers');
		is($down_hits, 0, 'random two: no request routed to check-down peer');

		($ok, $down_hits) = probe('/chash', 40, 1);
		is($ok, 40, 'chash: all requests routed to healthy peers');
		is($down_hits, 0, 'chash: no request routed to check-down peer');

		like(http_get('/random_down'), qr/502 Bad Gateway/,
			'random: all peers check-down returns 502');
		like(http_get('/random2_down'), qr/502 Bad Gateway/,
			'random two: all peers check-down returns 502');
		like(http_get('/chash_down?a=1'), qr/502 Bad Gateway/,
			'chash: all peers check-down returns 502');
	}
}

###############################################################################

sub wait_status {
	my ($up_re, $up_expected, $down_re, $down_expected) = @_;
	my $last;

	for (1 .. 50) {
		$last = http_get('/status');
		if (defined $last) {
			my @up = ($last =~ /$up_re/g);
			my @down = ($last =~ /$down_re/g);
			return (1, $last)
				if @up == $up_expected && @down == $down_expected;
		}
		select undef, undef, undef, 0.1;
	}

	return (0, $last);
}

sub chash_port {
	my ($key) = @_;
	my $r = http_get("/chash?a=$key");
	if (defined $r && $r =~ /200 OK/ && $r =~ /X-Port: (\d+)/) {
		return $1;
	}
	return undef;
}

sub probe {
	my ($uri, $count, $vary_key) = @_;
	my ($healthy, $down) = (0, 0);

	for my $i (1 .. $count) {
		my $req = $vary_key ? "$uri?a=$i" : $uri;
		my $r = http_get($req);

		if (defined $r && $r =~ /200 OK/ && $r =~ /X-Port: (\d+)/) {
			if ($1 == $p1 || $1 == $p2) {
				$healthy++;
			} elsif ($1 == $p3 || $1 == $p4) {
				$down++;
			}
		}
	}

	return ($healthy, $down);
}

###############################################################################
