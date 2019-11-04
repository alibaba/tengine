#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream ip_hash balancer with IPv6 and unix sockets.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_ip_hash realip unix/)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        ip_hash;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-IP $remote_addr always;

        location / {
            set_real_ip_from 127.0.0.0/8;
            proxy_pass http://u;
        }

        location /unix {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock;
            proxy_set_header X-Real-IP $http_x_real_ip;
        }

        location /ipv6 {
            proxy_pass http://[::1]:%%PORT_8080%%;
            proxy_set_header X-Real-IP $http_x_real_ip;
        }
    }

    server {
        listen       unix:%%TESTDIR%%/unix.sock;
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location / {
            set_real_ip_from unix:;
            set_real_ip_from ::1;
            proxy_pass http://u;
        }

        location /unix/none {
            proxy_pass http://u;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        location / {
            add_header X-Port $server_port always;
        }
    }
}

EOF

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/') !~ /X-IP: 127.0.0.1/m;

$t->try_run('no inet6 support')->plan(4);

###############################################################################

my @ports = my ($port1, $port2) = (port(8081), port(8082));

is(many('/unix', 30), "$port1: 15, $port2: 15", 'ip_hash realip via unix');
is(many('/ipv6', 30), "$port1: 15, $port2: 15", 'ip_hash realip via ipv6');

is(many_ip6('/', 30), "$port1: 15, $port2: 15", 'ip_hash ipv6');
like(many('/unix/none', 30), qr/($port1|$port2): 30/, 'ip_hash unix');

###############################################################################

sub many {
	my ($uri, $count) = @_;
	my %ports;

	for my $i (1 .. $count) {
		my $req = "GET $uri HTTP/1.0" . CRLF
			. "X-Real-IP: 127.0.$i.2" . CRLF . CRLF;

		if (http($req) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

sub many_ip6 {
	my ($uri, $count) = @_;
	my %ports;

	for my $i (1 .. $count) {
		my $req = "GET $uri HTTP/1.0" . CRLF
			. "X-Real-IP: ::$i" . CRLF . CRLF;

		if (http($req) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################
