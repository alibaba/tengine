#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for worker_shutdown_timeout and HTTP/2 with proxy.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_shutdown_timeout 10ms;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 5s;
        }
    }
}
EOF

$t->run_daemon(\&http_silent_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $s = Test::Nginx::HTTP2->new();
ok($s->new_stream(), 'new stream');

$s->h2_ping('SEE-THIS');
$s->read(all => [{ type => 'PING' }]);

$t->stop();

like($t->read_file('access.log'), qr/ (?!504)\d{3} /, 'shutdown timeout');

###############################################################################

sub http_silent_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) { }
	}
}

###############################################################################
