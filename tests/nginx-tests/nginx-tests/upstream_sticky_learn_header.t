#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for sticky upstreams ('learn' method, 'header' parameter).

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy upstream_sticky/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_sticky {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z1:1m timeout=2
               lookup=$cookie_sid create=$cookie_sid;
    }

    upstream u_sticky_header {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z2:1m timeout=2 header
               lookup=$cookie_sid create=$cookie_sid;
    }

    upstream u_sticky_header_srv {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky learn zone=z3:1m timeout=2 header
               lookup=$cookie_sid create=$upstream_cookie_sid;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_buffering off;

        location / {
            proxy_pass http://u_sticky/long;
        }

        location /header {
            proxy_pass http://u_sticky_header/long;
        }

        location /header_srv {
            proxy_pass http://u_sticky_header_srv/long;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        location /long {
            limit_rate 10000;
            add_header X-Port $server_port;
            add_header Set-Cookie sid=baz;
        }
    }
}

EOF

$t->write_file('long', 'x' x 40000);
$t->try_run('no sticky learn header')->plan(3);

###############################################################################

my @ports = my ($p1, $p2) = (port(8081), port(8082));

my $s1 = http_get_multi('/', 4, 'sid=foo');
my $s2 = http_get_multi('/header', 4, 'sid=bar');
my $s3 = http_get_multi('/header_srv', 4, 'sid=baz');

is(http_end_multi($s1), "$p1: 2, $p2: 2", 'sticky learn - balanced');
is(http_end_multi($s2), "$p1: 4", 'sticky learn from header');
is(http_end_multi($s3), "$p1: 4", 'sticky learn from upstream header');

###############################################################################

sub http_get_cookie {
	my ($url, $cookie, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF
}

sub http_get_multi {
	my ($uri, $count, $cookie) = @_;
	my @sockets;

	for (0 .. $count - 1) {
		$sockets[$_] = http_get_cookie($uri, $cookie, start => 1);
		IO::Select->new($sockets[$_])->can_read(1);
	}

	return [@sockets];
}

sub http_end_multi {
	my ($sockets) = @_;
	my %ports;

	for my $sock (@$sockets) {
		if (http_end($sock) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################
