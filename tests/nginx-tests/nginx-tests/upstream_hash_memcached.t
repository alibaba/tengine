#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream hash balancer module distribution consistency
# with Cache::Memcached and Cache::Memcached::Fast.

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

eval { require Cache::Memcached; };
plan(skip_all => 'Cache::Memcached not installed') if $@;
eval { require Cache::Memcached::Fast; };
plan(skip_all => 'Cache::Memcached::Fast not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http rewrite memcached upstream_hash/)
	->has_daemon('memcached')->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream memd {
        hash $arg_a;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
    }

    upstream memd_c {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
    }

    upstream memd_w {
        hash $arg_a;
        server 127.0.0.1:8081 weight=2;
        server 127.0.0.1:8082 weight=3;
        server 127.0.0.1:8083;
    }

    upstream memd_cw {
        hash $arg_a consistent;
        server 127.0.0.1:8081 weight=2;
        server 127.0.0.1:8082 weight=3;
        server 127.0.0.1:8083;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        set $memcached_key $arg_a;

        location / {
            memcached_pass memd;
        }
        location /c {
            memcached_pass memd_c;
        }
        location /w {
            memcached_pass memd_w;
        }
        location /cw {
            memcached_pass memd_cw;
        }
    }
}

EOF

my $memhelp = `memcached -h`;
my @memopts = ();

if ($memhelp =~ /repcached/) {
	# repcached patch adds additional listen socket
	push @memopts, '-X', '0';
}
if ($memhelp =~ /-U/) {
	# UDP port is on by default in memcached 1.2.7+
	push @memopts, '-U', '0';
}

$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', port(8081), @memopts);
$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', port(8082), @memopts);
$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', port(8083), @memopts);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081)) or die "Can't start memcached";
$t->waitforsocket('127.0.0.1:' . port(8082)) or die "Can't start memcached";
$t->waitforsocket('127.0.0.1:' . port(8083)) or die "Can't start memcached";

###############################################################################

my $memd1 = Cache::Memcached->new(servers => [ '127.0.0.1:' . port(8081) ],
	connect_timeout => 1.0);
my $memd2 = Cache::Memcached->new(servers => [ '127.0.0.1:' . port(8082) ],
	connect_timeout => 1.0);
my $memd3 = Cache::Memcached->new(servers => [ '127.0.0.1:' . port(8083) ],
	connect_timeout => 1.0);

for my $i (1 .. 20) {
	$memd1->set($i, port(8081)) or die "can't put value into memcached: $!";
	$memd2->set($i, port(8082)) or die "can't put value into memcached: $!";
	$memd3->set($i, port(8083)) or die "can't put value into memcached: $!";
}

my $memd = new Cache::Memcached(servers => [
	'127.0.0.1:' . port(8081),
	'127.0.0.1:' . port(8082),
	'127.0.0.1:' . port(8083) ]);

is_deeply(ngx('/'), mem($memd), 'cache::memcached');

$memd = new Cache::Memcached::Fast({ ketama_points => 160, servers => [
	'127.0.0.1:' . port(8081),
	'127.0.0.1:' . port(8082),
	'127.0.0.1:' . port(8083)] });

# Cache::Memcached::Fast may be incompatible with recent Perl,
# see https://github.com/JRaspass/Cache-Memcached-Fast/issues/12

my $cmf_bug = ! keys %{$memd->server_versions};

SKIP: {
skip 'Cache::Memcached::Fast bug', 1 if $cmf_bug;

is_deeply(ngx('/c'), mem($memd), 'cache::memcached::fast');

}

$memd = new Cache::Memcached(servers => [
	[ '127.0.0.1:' . port(8081), 2 ],
	[ '127.0.0.1:' . port(8082), 3 ],
	[ '127.0.0.1:' . port(8083), 1 ]]);

is_deeply(ngx('/w'), mem($memd), 'cache::memcached weight');

$memd = new Cache::Memcached::Fast({ ketama_points => 160, servers => [
	{ address => '127.0.0.1:' . port(8081), weight => 2 },
	{ address => '127.0.0.1:' . port(8082), weight => 3 },
	{ address => '127.0.0.1:' . port(8083), weight => 1 }] });

SKIP: {
skip 'Cache::Memcached::Fast bug', 1 if $cmf_bug;

is_deeply(ngx('/cw'), mem($memd), 'cache::memcached::fast weight');

}

###############################################################################

sub ngx {
	my ($uri) = @_;
	[ map { http_get("/$uri?a=$_") =~ /^(\d+)/ms && $1; } (1 .. 20) ];
}

sub mem {
	my ($memd) = @_;
	[ map { $memd->get($_); } (1 .. 20) ];
}

###############################################################################
