#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams ('learn' method).

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_sticky/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_sticky_cl {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z1:1m timeout=2
               lookup=$cookie_sid create=$cookie_sid;
    }

    upstream u_sticky {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z2:1m timeout=2
               create=$upstream_cookie_sid lookup=$cookie_sid;
    }

    upstream u_sticky_case_cl {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z3:1m timeout=2
               lookup=$cookie_sid create=$cookie_sid;
    }

    upstream u_sticky_case {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z4:1m timeout=2
               create=$upstream_cookie_sid lookup=$cookie_sid;
    }

    upstream u_sticky_live {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z5:1m timeout=3
               create=$upstream_cookie_sid lookup=$cookie_sid;
    }

    upstream u_sticky_mismatch {
        server 127.0.0.1:8081; # drain;
        server 127.0.0.1:8082; # drain;
        # server 127.0.0.1:8083;
        # server 127.0.0.1:8084;

        sticky learn zone=z6:1m timeout=2
               create=$upstream_cookie_sid lookup=$cookie_sid;
    }

    upstream u_sticky_mismatch_to {
        server 127.0.0.1:8081; # drain;
        server 127.0.0.1:8082; # drain;
        # server 127.0.0.1:8083;
        # server 127.0.0.1:8084;

        sticky learn zone=z7:1m timeout=5
               create=$upstream_cookie_sid lookup=$cookie_sid;
    }

    upstream u_sticky_route {
        server 127.0.0.1:8081 route=a;
        server 127.0.0.1:8082 route=b;
        sticky learn zone=z8:1m timeout=2
               create=$cookie_sid lookup=$cookie_sid;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /server {
            proxy_pass http://u_sticky/;
        }
        location /client {
            proxy_pass http://u_sticky_cl/;
            proxy_next_upstream http_403 http_502;
            add_header X-Status $upstream_status;
        }

        location /server_case {
            proxy_pass http://u_sticky_case;
        }
        location /client_case {
            proxy_pass http://u_sticky_case_cl;
        }

        location /server_live {
            proxy_pass http://u_sticky_live/;
        }
        location /server_mismatch {
            proxy_pass http://u_sticky_mismatch/;
        }
        location /server_mismatch_timeout {
            proxy_pass http://u_sticky_mismatch_to/;
        }

        location /route {
            proxy_pass http://u_sticky_route/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8083;
        server_name  localhost;

        location / {
            add_header Set-Cookie sid=value1;
            add_header X-Port $server_port;
            return 200;
        }
        location /swap {
            add_header Set-Cookie sid=value2;
            add_header X-Port $server_port;
            return 200;
        }
        location /no_cookie {
            add_header X-Port $server_port;
            return 200;
        }
        location /403 {
            return 403;
        }
        location /502 {
            return 502;
        }
    }

    server {
        listen       127.0.0.1:8082;
        listen       127.0.0.1:8084;
        server_name  localhost;

        location / {
            add_header Set-Cookie sid=value2;
            add_header X-Port $server_port;
            return 200;
        }
        location /swap {
            add_header Set-Cookie sid=value1;
            add_header X-Port $server_port;
            return 200;
        }
        location /no_cookie {
            add_header X-Port $server_port;
            return 200;
        }
        location /444 {
            # not listed in proxy_next_upstream
            return 444;
        }
        location /long {
            limit_rate 10000;
        }
    }
}

EOF

$t->write_file('long', 'x' x 40000);
$t->try_run('no sticky learn')->plan(30);

###############################################################################

my @ports = my ($p1, $p2, $p3, $p4) = (port(8081), port(8082), port(8083),
	port(8084));

# non-sticky requests are balanced as usual

is(many('/server', 4), "$p1: 2, $p2: 2", 'balanced no cookie server');
is(many('/client', 4), "$p1: 2, $p2: 2", 'balanced no cookie client');

# no sticky session if client sends cookie not present on peers

is(many('/server', 4, cookie => 'sid=absent'), "$p1: 2, $p2: 2",
	'balanced no session');

# sticky session is established if client sends cookie present on peer

is(many('/server', 4, cookie => 'sid=value1'), "$p1: 4", 'sticky server 1');
is(many('/server', 4, cookie => 'sid=value2'), "$p2: 4", 'sticky server 2');

# client initiated session, stick with selected peer

is(many('/client', 4, cookie => 'sid=value1'), "$p1: 4", 'sticky client 1');

# with different client cookie, new sticky session is assigned to selected peer

is(many('/client', 4, cookie => 'sid=value2'), "$p2: 4", 'sticky client 2');
is(many('/client', 4, cookie => 'sid=value3'), "$p1: 4", 'sticky client 3');

# known cookie again, take sticky peer

is(many('/client', 4, cookie => 'sid=value1'), "$p1: 4", 'sticky client 1 1');


# proxy next upstream tests
# sticky peer:8081 returns HTTP error listed in proxy_next_upstream, try next

my $r = http_get_cookie('/client/403', cookie => 'sid=value1');
like($r, qr/X-Port: $p2/, 'pnu 403 port');
like($r, qr/X-Status: 403, 200(?!,)/, 'pnu 403 status');

# sticky session moved to another previously selected peer:8082

$r = http_get_cookie('/client/403', cookie => 'sid=value1');
like($r, qr/X-Port: $p2/, 'pnu 403 port new sticky');
like($r, qr/X-Status: 200(?!,)/, 'pnu 403 status new sticky');

# proxy_next_upstream, unsuccessful attempts, fails sticky peer:8081

$r = http_get_cookie('/client/502', cookie => 'sid=value3');
like($r, qr/X-Port: $p2/, 'pnu 502 port');
like($r, qr/X-Status: 502, 200(?!,)/, 'pnu 502 status');

$r = http_get_cookie('/client/502', cookie => 'sid=value3');
like($r, qr/X-Port: $p2/, 'pnu 502 port new sticky');
like($r, qr/X-Status: 200(?!,)/, 'pnu 502 status new sticky');


# with sticky learn timeout, new sticky peer is selected by balancer

many('/server_live', 4);
many('/server_mismatch', 4);
many('/server_mismatch_timeout', 4);

is(many('/server_live', 4, cookie => 'sid=value2'), "$p2: 4",
	'sticky timeout before live');
is(many('/server_mismatch', 4, cookie => 'sid=value2'), "$p2: 4",
	'sticky timeout before mismatch');

my $conf = $t->read_file('nginx.conf');

$conf =~ s/; # drain;/ drain;/g;
$conf =~ s/# server/server/g;

$t->write_file('nginx.conf', $conf);

ok(reload($t), 'reload');

for (1 .. 5) {
	select undef, undef, undef, 0.5;
	many('/server_live/no_cookie', 4, cookie => 'sid=value2');
	many('/server_mismatch/swap', 4, cookie => 'sid=value2');
	many('/server_mismatch_timeout/swap', 4, cookie => 'sid=value2');
}

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.6');

# after timeout, requests are not initially sticky until balanced to 2nd peer

isnt(many('/server', 4, cookie => 'sid=value2'), "$p2: 4",
	'sticky timeout after');
is(many('/server', 4, cookie => 'sid=value2'), "$p2: 4",
	'sticky timeout sticky');

# if there were requests, they would prolong existing sticky session

is(many('/server_live/no_cookie', 4, cookie => 'sid=value2'), "$p2: 4",
	'sticky timeout sticky live');

# if there were requests with mismatching server-side cookie,
# such sticky session would expire and be replaced with a new one

like(many('/server_mismatch/swap', 4, cookie => 'sid=value2'), qr/($p3|$p4): 4/,
	'sticky timeout sticky mismatch');

# if there were mismatching server-side cookie, and response was received
# after session timeout, such sticky session might not be expired on time

many('/server_mismatch_timeout/long', 1, cookie => 'sid=value2');
unlike(many('/server_mismatch_timeout/swap', 4, cookie => 'sid=value2'),
	qr/($p1|$p2): /, 'sticky timeout sticky mismatch timeout');
}

# case sensitive tests

many('/server_case', 4);

# variable name is caseless

$r = many('/client_case', 1, cookie => 'sid=value');
is(many('/client_case', 1, cookie => 'SID=value'), $r, 'client caseless var');
is(many('/server_case', 4, cookie => 'SID=value2'), "$p2: 4",
	'server caseless var');

# variable value is caseful

$r = many('/client_case', 1, cookie => 'sid=value');
isnt(many('/client_case', 1, cookie => 'sid=VALUE'), $r,
	'client caseful value');
isnt(many('/server_case', 4, cookie => 'sid=VALUE2'), "$p2: 4",
	'server caseful value');


# sticky learn with server route parameter

is(many('/route', 4, cookie => 'sid=value2'), "$p1: 4", 'route');

###############################################################################

sub http_get_cookie {
	my ($url, %extra) = @_;
	my $cookie = $extra{cookie};
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF
}

sub many {
	my ($uri, $count, %opts) = @_;
	my %ports;

	my $cookie = $opts{cookie};
	my $http_getp = $cookie ? \&http_get_cookie : \&http_get;

	for (1 .. $count) {
		if (&{$http_getp}($uri, %opts) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}

		select undef, undef, undef, $opts{delay} if $opts{delay};
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub reload {
	my ($t) = @_;

	$t->reload();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /exited with code/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
