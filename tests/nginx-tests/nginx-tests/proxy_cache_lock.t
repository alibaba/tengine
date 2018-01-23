#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache lock.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache shmem/)->plan(17)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
        }

        location /timeout {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
            proxy_cache_lock_timeout 200ms;
        }

        location /nolock {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
        }
    }
}

EOF

$t->run_daemon(\&http_fake_daemon);

$t->run();

$t->waitforsocket('127.0.0.1:8081');

###############################################################################

# sequential requests

for my $i (1 .. 5) {
	like(http_get('/seq'), qr/request 1/, 'sequential request ' . $i);
}

# parallel requests

my @sockets;

for my $i (1 .. 5) {
	$sockets[$i] = http_get('/par1', start => 1);
}

for my $i (1 .. 5) {
	like(http_end($sockets[$i]), qr/request 1/, 'parallel request ' . $i);
}

like(http_get('/par1'), qr/request 1/, 'first request cached');

# since 1.7.8, parallel requests with cache lock timeout expired are not cached

for my $i (1 .. 3) {
	$sockets[$i] = http_get('/timeout', start => 1);
}

like(http_end($sockets[1]), qr/request 1/, 'lock timeout - first');

my $rest = http_end($sockets[2]);
$rest .= http_end($sockets[3]);

like($rest, qr/request (2.*request 3|3.*request 2)/s, 'lock timeout - rest');
like(http_get('/timeout'), qr/request 1/, 'lock timeout - first only cached');

# no lock

for my $i (1 .. 3) {
	$sockets[$i] = http_get('/nolock', start => 1);
}

like(http_end($sockets[1]), qr/request 1/, 'nolock - first');

$rest = http_end($sockets[2]);
$rest .= http_end($sockets[3]);

like($rest, qr/request (2.*request 3|3.*request 2)/s, 'nolock - rest');
like(http_get('/nolock'), qr/request 3/, 'nolock - last cached');

###############################################################################

sub http_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $num = 0;
	my $uri = '';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			if (/GET (.*) HTTP/ && $1 ne $uri) {
				$uri = $1;
				$num = 0;
			}

			$uri = $1 if /GET (.*) HTTP/;
			last if /^\x0d?\x0a?$/;
		}

		next unless $uri;

		select(undef, undef, undef, 1.1);

		$num++;
		print $client <<"EOF";
HTTP/1.1 200 OK
Cache-Control: max-age=300
Connection: close

request $num
EOF
	}
}

###############################################################################
