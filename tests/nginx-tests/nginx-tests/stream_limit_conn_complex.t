#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream limit_conn module.

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

my $t = Test::Nginx->new()->has(qw/http stream stream_limit_conn/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

stream {
    limit_conn_zone  $binary_remote_addr$server_port  zone=zone:1m;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8084;
        limit_conn  zone 1;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8084;
        limit_conn  zone 1;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('index.html', '');
$t->run()->plan(4);

###############################################################################

like(get(port(8080)), qr/200 OK/, 'passed');

my $s = http(<<EOF, start => 1, sleep => 0.2);
GET / HTTP/1.0
EOF

ok($s, 'long connection');

is(get(port(8080)), undef, 'rejected same key');
like(get(port(8081)), qr/200 OK/, 'passed different key');

###############################################################################

sub get {
	my $port = shift;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => "127.0.0.1:$port"
	)
		or die "Can't connect to nginx: $!\n";

	my $r = http_get('/', socket => $s);
	if (!$r) {
		$r = undef;
	}

	return $r;
}

###############################################################################
