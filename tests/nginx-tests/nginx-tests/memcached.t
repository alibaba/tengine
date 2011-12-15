#!/usr/bin/perl

# (C) Maxim Dounin

# Test for memcached backend.

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

my $t = Test::Nginx->new()->has(qw/http rewrite memcached/)
	->has_daemon('memcached')->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            set $memcached_key $uri;
            memcached_pass 127.0.0.1:8081;
        }

        location /next {
            set $memcached_key $uri;
            memcached_next_upstream  not_found;
            memcached_pass 127.0.0.1:8081;
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
$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Can't start memcached";

###############################################################################

my $memd = Cache::Memcached->new(servers => [ '127.0.0.1:8081' ]);
$memd->set('/', 'SEE-THIS')
	or die "can't put value into memcached: $!";

like(http_get('/'), qr/SEE-THIS/, 'memcached request');

like(http_get('/notfound'), qr/404/, 'memcached not found');

like(http_get('/next'), qr/404/, 'not found with memcached_next_upstream');

unlike(http_head('/'), qr/SEE-THIS/, 'memcached no data in HEAD');

###############################################################################
