#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module with memcached.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require Cache::Memcached; };
plan(skip_all => 'Cache::Memcached not installed') if $@;

eval { require IO::Compress::Gzip; };
plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has(qw/http gunzip memcached rewrite/)
	->has_daemon('memcached')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        gunzip on;

        location / {
            set $memcached_key $uri;
            memcached_pass 127.0.0.1:8081;
            memcached_gzip_flag 2;
        }
    }
}

EOF

my $memhelp = `memcached -h`;
my @memopts = ();

if ($memhelp =~ /repcached/) {
	# repcached patch adds additional listen socket
	push @memopts, '-X', '8082';
}
if ($memhelp =~ /-U/) {
	# UDP port is on by default in memcached 1.2.7+
	push @memopts, '-U', '0';
}

$t->run_daemon('memcached', '-l', '127.0.0.1', '-p', '8081', @memopts);

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no memcached_gzip_flag') if $@;

$t->plan(2);

$t->waitforsocket('127.0.0.1:8081')
	or die "Can't start memcached";

# Put compressed value into memcached.  This requires compress_threshold to be
# set and compressed value to be at least 20% less than original one.

my $memd = Cache::Memcached->new(servers => [ '127.0.0.1:8081' ],
	compress_threshold => 1);
$memd->set('/', 'TEST' x 10)
        or die "can't put value into memcached: $!";

###############################################################################

http_gzip_like(http_gzip_request('/'), qr/TEST/, 'memcached response gzipped');
like(http_get('/'), qr/TEST/, 'memcached response gunzipped');

###############################################################################
