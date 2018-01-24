#!/usr/bin/perl

# (C) Maxim Dounin

# Test for memcached with keepalive.

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
	->has_daemon('memcached')->plan(15)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream memd {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    upstream memd3 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        keepalive 1;
    }

    upstream memd4 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        keepalive 10;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            set $memcached_key $uri;
            memcached_pass memd;
        }

        location /next {
            set $memcached_key $uri;
            memcached_next_upstream  not_found;
            memcached_pass memd;
        }

        location /memd3 {
            set $memcached_key "/";
            memcached_pass memd3;
        }

        location /memd4 {
            set $memcached_key "/";
            memcached_pass memd4;
        }
    }
}

EOF

my $memhelp = `memcached -h`;
my @memopts1 = ();
my @memopts2 = ();

if ($memhelp =~ /repcached/) {
	# repcached patches adds additional listen socket memcached
	# that should be different too

	push @memopts1, '-X', '8091';
	push @memopts2, '-X', '8092';
}
if ($memhelp =~ /-U/) {
	# UDP ports no longer off by default in memcached 1.2.7+

	push @memopts1, '-U', '0';
	push @memopts2, '-U', '0';
}
if ($memhelp =~ /-t/) {
	# for connection stats consistency in threaded memcached 1.3+

	push @memopts1, '-t', '1';
	push @memopts2, '-t', '1';
}

$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', '8081', @memopts1);
$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', '8082', @memopts2);

$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Unable to start memcached";
$t->waitforsocket('127.0.0.1:8082')
	or die "Unable to start second memcached";

###############################################################################

my $memd1 = Cache::Memcached->new(servers => [ '127.0.0.1:8081' ],
	connect_timeout => 1.0);
my $memd2 = Cache::Memcached->new(servers => [ '127.0.0.1:8082' ],
	connect_timeout => 1.0);

$memd1->set('/', 'SEE-THIS');
$memd2->set('/', 'SEE-THIS');
$memd1->set('/big', 'X' x 1000000);

my $total = $memd1->stats()->{total}->{total_connections};

like(http_get('/'), qr/SEE-THIS/, 'keepalive memcached request');
like(http_get('/notfound'), qr/ 404 /, 'keepalive memcached not found');
like(http_get('/next'), qr/ 404 /,
	'keepalive not found with memcached_next_upstream');
like(http_get('/'), qr/SEE-THIS/, 'keepalive memcached request again');
like(http_get('/'), qr/SEE-THIS/, 'keepalive memcached request again');
like(http_get('/'), qr/SEE-THIS/, 'keepalive memcached request again');

is($memd1->stats()->{total}->{total_connections}, $total + 1,
	'only one connection used');

# Since nginx doesn't read all data from connection in some situations (head
# requests, post_action, errors writing to client) we have to close such
# connections.  Check if we really do close them.

$total = $memd1->stats()->{total}->{total_connections};

unlike(http_head('/'), qr/SEE-THIS/, 'head request');
like(http_get('/'), qr/SEE-THIS/, 'get after head');

is($memd1->stats()->{total}->{total_connections}, $total + 1,
	'head request closes connection');

$total = $memd1->stats()->{total}->{total_connections};

unlike(http_head('/big'), qr/XXX/, 'big head');
like(http_get('/'), qr/SEE-THIS/, 'get after big head');

is($memd1->stats()->{total}->{total_connections}, $total + 1,
	'big head request closes connection');

# two backends with maximum number of cached connections set to 1,
# should establish new connection on each request

$total = $memd1->stats()->{total}->{total_connections} +
	$memd2->stats()->{total}->{total_connections};

http_get('/memd3');
http_get('/memd3');
http_get('/memd3');

is($memd1->stats()->{total}->{total_connections} +
	$memd2->stats()->{total}->{total_connections}, $total + 3,
	'3 connections should be established');

# two backends with maximum number of cached connections set to 10,
# should establish only two connections (1 per backend)

$total = $memd1->stats()->{total}->{total_connections} +
	$memd2->stats()->{total}->{total_connections};

http_get('/memd4');
http_get('/memd4');
http_get('/memd4');

is($memd1->stats()->{total}->{total_connections} +
	$memd2->stats()->{total}->{total_connections}, $total + 2,
	'connection per backend');

###############################################################################
