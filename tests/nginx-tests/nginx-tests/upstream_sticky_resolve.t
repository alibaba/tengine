#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams (cookie mode) with re-resolvable servers.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_sticky/)
	->has(qw/upstream_zone/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    # lower the retry timeout after empty reply
    resolver 127.0.0.1:%%PORT_8987_UDP%% valid=1s;
    # retry query shortly after DNS is started
    resolver_timeout 1s;

    server {
        listen 127.0.0.1:8081;
        location / {
            return 200 "backend_0";
        }
    }

    server {
        listen 127.0.0.1:8082;
        location / {
            return 200 "backend_1";
        }
    }

    server {
        listen 127.0.0.1:8083;
        location / {
            return 200 "backend_2";
        }
    }

    server {
        listen 127.0.0.1:8084;
        location / {
            return 200 "backend_3";
        }
    }

    server {
        listen 127.0.0.1:8086;
        location / {
            return 502 "backend_4";
        }
    }

    upstream u_backend_0 {
        zone u_backend_0 1m;
        server 127.0.0.1:8081;
        sticky cookie "sticky";
    }

    upstream u_backend_1 {
        zone u_backend_1 1m;
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    upstream u_backend_2 {
        zone u_backend_2 1m;
        server 127.0.0.1:8083;
        sticky cookie "sticky";
    }

    upstream u_backend_3 {
        zone u_backend_3 1m;
        server 127.0.0.1:8084;
        sticky cookie "sticky";
    }

    upstream u_backend_4 {
        zone u_backend_4 1m;
        server 127.0.0.1:8086;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky {
        zone u_rr_sticky 1m;
        server example.net:%%PORT_8081%% resolve;
        server example.net:%%PORT_8082%% resolve;
        server example.net:%%PORT_8083%% resolve;
        server example.net:%%PORT_8084%% resolve;
        sticky cookie "sticky";
    }

    upstream u_sticky_with_down {
        zone u_sticky_with_down 1m;
        # good servers
        server example.net:%%PORT_8081%% resolve;
        server example.net:%%PORT_8082%% resolve;
        server example.net:%%PORT_8083%% down resolve;
        server example.net:%%PORT_8084%% down resolve;
        sticky cookie sticky;
    }

    upstream u_pnu {
        zone u_pnu 1m;
        # bad server
        server example.net:%%PORT_8086%% max_fails=2 resolve;
        # good servers
        server example.net:%%PORT_8081%% resolve;
        server example.net:%%PORT_8082%% resolve;
        server example.net:%%PORT_8083%% resolve;
        sticky cookie sticky;
    }

    # no alive peers
    upstream u_sticky_dead {
        zone u_sticky_dead 1m;
        server example.net:%%PORT_8081%% down resolve;
        sticky cookie sticky;
    }

    upstream u_no_sticky {
        zone u_no_sticky 1m;
        server example.net:%%PORT_8081%% resolve;
        server example.net:%%PORT_8082%% resolve;
        server example.net:%%PORT_8083%% resolve;
        server example.net:%%PORT_8084%% resolve;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # to catch incorrect locations in test code
        location / {
            return 502;
        }

        # to access the single backend definitely with sticky
        location /backend_0 {
            proxy_pass http://u_backend_0;
        }
        location /backend_1 {
            proxy_pass http://u_backend_1;
        }
        location /backend_2 {
            proxy_pass http://u_backend_2;
        }
        location /backend_3 {
            proxy_pass http://u_backend_3;
        }
        location /backend_4 {
            proxy_pass http://u_backend_4;
        }

        location /rr_sticky {
            proxy_pass http://u_rr_sticky;
        }

        location /rr_sticky_with_down {
            proxy_pass http://u_sticky_with_down;
        }

        location /rr_sticky_dead {
            proxy_pass http://u_sticky_dead;
        }

        location /no_sticky {
            proxy_pass http://u_no_sticky;
        }

        location /pnu {
            proxy_pass http://u_pnu;
            proxy_next_upstream http_502;
        }
    }
}

EOF

$t->run_daemon(\&dns_daemon, $t)->waitforfile($t->testdir . '/' . port(8987));
$t->try_run('no sticky upstream')->plan(14);

###############################################################################

my %backend_cookies;
my $re = qr/(.*?)\x0d\x0a?/;
my ($response, $cookie, $backend);

# record cookies returned by each backend server for use in tests
collect_backend_cookies(4, \%backend_cookies);

# verify sticky, cookie always presents in the response

($cookie, $backend) = sticky_request('/rr_sticky', 0);
is($cookie, $backend_cookies{0}, 'sticky cookie always set');
is($backend, 'backend_0', 'request to server 0');

($cookie, $backend) = sticky_request('/rr_sticky', 1);
is($cookie, $backend_cookies{1}, 'sticky cookie always set');
is($backend, 'backend_1', 'request to server 1');

($cookie, $backend) = sticky_request('/rr_sticky', 2);
is($cookie, $backend_cookies{2}, 'sticky cookie always set');
is($backend, 'backend_2', 'request to server 2');

($cookie, $backend) = sticky_request('/rr_sticky', 3);
is($cookie, $backend_cookies{3}, 'sticky cookie always set');
is($backend, 'backend_3', 'request to server 3');

# miscellaneous tests

($cookie) = http_get('/no_sticky') =~ /Set-Cookie: sticky=$re/;
ok(!defined($cookie), "no sticky cookies for non-sticky upstream");

# Sticky request to a backend marked as down => new cookie expected
($cookie, $backend) = sticky_request('/rr_sticky_with_down', 3);
($backend) = $backend =~ /backend_(\d)/;

is($cookie, $backend_cookies{$backend},
	'new cookie is set if requested server is \'down\'');

# Stress test: request to dead upstream, expecting to get 500 without cookies

($cookie, $backend) = sticky_request('/rr_sticky_dead', 0);

ok(!defined($cookie), 'no cookie for dead upstream');
like($backend, qr/502 Bad Gateway/, '502 is returned for dead upstream');

# proxy_next_upstream test

# prepare for test: get cookie for backend 4 that returns 502
$response = http_get("/backend_4");
($backend) = $response =~ /backend_(\d+)/;
($cookie) = $response =~ /Set-Cookie: sticky=$re/;
$backend_cookies{$backend} = $cookie;

# sticky request to 4: will get 502 from 4, then 200
($cookie, $backend) = sticky_request('/pnu', 4);
($backend) = $backend =~ /backend_(\d)/;

like($backend, qr/^[012]$/, "sticky request switched to next upstream");
is($cookie, $backend_cookies{$backend},
	'sticky cookie is ok for next upstream');

###############################################################################

# walk through all backends (each is the only in own upstream) to get cookies
sub collect_backend_cookies {
	my ($server_cnt, $backend_cookies) = @_;

	my ($response, $backend, $cookie);

	for my $n (0 .. ($server_cnt - 1)) {
		my $uri = '/backend_'.$n;

		$response = http_get($uri);
		($backend) = $response =~ /backend_(\d+)/;
		($cookie) = $response =~ /Set-Cookie: sticky=$re/;

		# We expect only good 'backend_N' responses
		if (!defined($backend)) {
			fail("request to '$uri' returned unexpected response");
			return;
		}

		# Each response must have a cookie set
		if (!defined($cookie)) {
			fail("request to '$uri' has no cookie");
			return;
		}
		$backend_cookies->{$backend} = $cookie;
	}
}

###############################################################################

# sends sticky request to particular backend
sub sticky_request {
	my ($uri, $backend_index) = @_;

	my $cookie = 'sticky='.$backend_cookies{$backend_index};

	my $request=<<EOF;
GET $uri HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF

	my $response = http($request);
	my ($response_cookie) = $response =~ /Set-Cookie: sticky=$re/;
	my $backend = http_content($response);
	return ($response_cookie, $backend);
}

###############################################################################

sub reply_handler {
	my ($recv_data) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;

	use constant A		=> 1;
	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl) = (0x8180, NOERROR, 1);

	# decode name

	my ($len, $offset) = (undef, 12);
	while (1) {
		$len = unpack("\@$offset C", $recv_data);
		last if $len == 0;
		$offset++;
		push @name, unpack("\@$offset A$len", $recv_data);
		$offset += $len;
	}

	$offset -= 1;
	my ($id, $type, $class) = unpack("n x$offset n2", $recv_data);

	my $name = join('.', @name);
	if ($name eq 'example.net' && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');
	}

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_addr {
	my ($ttl, $addr) = @_;

	my $code = 'split(/\./, $addr)';

	pack 'n3N nC4', 0xc00c, A, IN, $ttl, eval "scalar $code", eval($code);
}

sub dns_daemon {
	my ($t) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => port(8987),
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8987);
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		$data = reply_handler($recv_data);
		$socket->send($data);
	}
}

###############################################################################
