#!/usr/bin/perl

# (C) Maxim Dounin

# Test for stale events handling in upstream keepalive.

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

my $t = Test::Nginx->new()->has(qw/http memcached upstream_keepalive rewrite/)
	->has_daemon('memcached')->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes 2;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream memd {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080 sndbuf=32k;
        server_name  localhost;

        location / {
            set $memcached_key $uri;
            memcached_pass memd;
        }
    }
}

EOF

my $memhelp = `memcached -h`;
my @memopts1 = ();

if ($memhelp =~ /repcached/) {
	# repcached patches adds additional listen socket memcached
	# that should be different too

	push @memopts1, '-X', '8091';
}
if ($memhelp =~ /-U/) {
	# UDP ports no longer off by default in memcached 1.2.7+

	push @memopts1, '-U', '0';
}
if ($memhelp =~ /-t/) {
	# for connection stats consistency in threaded memcached 1.3+

	push @memopts1, '-t', '1';
}

$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', '8081', @memopts1);

$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Unable to start memcached";

###############################################################################

my $memd1 = Cache::Memcached->new(servers => [ '127.0.0.1:8081' ],
	connect_timeout => 1.0);

# It's possible that stale events occur, i.e. read event handler called
# for just saved upstream connection without any data available for
# read.  We shouldn't close upstream connection in such situation.
#
# This happens due to reading from upstream connection on downstream write
# events.  More likely to happen with multiple workers due to use of posted
# events.
#
# Stale event may only happen if reading response from upstream requires
# entering event loop, i.e. response should be big enough.  On the other
# hand, it is less likely to occur with full client's connection output
# buffer.
#
# We use here 2 workers, 20k response and set output buffer on clients
# connection to 32k.  This allows more or less reliably reproduce stale
# events at least on FreeBSD testbed here.

$memd1->set('/big', 'X' x 20480);

my $total = $memd1->stats()->{total}->{total_connections};

for (1 .. 100) {
	http_get('/big');
}

cmp_ok($memd1->stats()->{total}->{total_connections}, '<=', $total + 2,
	'only one connection per worker used');

###############################################################################
