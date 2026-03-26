#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams ('route' method) with drain feature.

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

    upstream u {
        server 127.0.0.1:8081 route=1;
        server 127.0.0.1:8082 route=2;
        server 127.0.0.1:8083 route=3;
        server 127.0.0.1:8084 route=4;
        sticky route $arg_sticky;
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        listen       127.0.0.1:8083;
        listen       127.0.0.1:8084;
        server_name  localhost;

        location / {
            return 200 "backend_$server_port";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }
    }
}

EOF

$t->try_run('no sticky upstream')->plan(7);

###############################################################################

my ($p0, $p1, $p2, $p3, $p4) = (port(8080), port(8081), port(8082), port(8083),
	port(8084));

is(rr('/', 16), (join ' ', map { $p1, $p2, $p3, $p4 } (1 .. 4)),
	'new requests rr');

is(sticky('/', 'sticky=1', 4), "$p1 $p1 $p1 $p1", 'sticky');

my $conf = $t->read_file('nginx.conf');

$conf =~ s/(:$p1 route=.*);/$1 drain;/;
$t->write_file('nginx.conf', $conf);

ok(reload($t, 1), 'reload - 1');

is(sticky('/', 'sticky=1', 4), "$p1 $p1 $p1 $p1", 'still sticky');

is(rr('/', 12), (join ' ', map { $p2, $p3, $p4 } (1 .. 4)), 'drained never rr');

$conf =~ s/server\s.*:$_\s.*;// for ($p2, $p3, $p4);
$t->write_file('nginx.conf', $conf);

ok(reload($t, 2), 'reload - 2');

is(sticky('/', 'sticky=1', 4), "$p1 $p1 $p1 $p1", 'still sticky - single');

###############################################################################

sub rr {
	my ($uri, $num) = @_;
	return join ' ', map { get_backend($uri) } (1 .. $num);
}

sub sticky {
	my ($uri, $key, $num) = @_;
	return join ' ', map { get_backend("$uri?$key") } (1 .. $num);
}

sub get_backend {
	my ($uri) = @_;
	return http_get($uri) =~ /backend_(\d+)/ && $1;
}

sub reload {
	my ($t, $exp) = @_;

	$t->reload();

	for (1 .. 30) {
		my @count = $t->read_file('error.log') =~ /exited with code/g;
		return 1 if @count == $exp;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
