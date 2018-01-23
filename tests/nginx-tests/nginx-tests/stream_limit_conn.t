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

my $t = Test::Nginx->new()->has(qw/http stream stream_limit_conn shmem/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    limit_conn_zone  $binary_remote_addr  zone=zone:1m;
    limit_conn_zone  $binary_remote_addr  zone=zone2:1m;

    server {
        listen           127.0.0.1:8080;
        proxy_pass       127.0.0.1:8084;
        limit_conn       zone 1;
    }

    server {
        listen           127.0.0.1:8085;
        proxy_pass       127.0.0.1:8084;
        limit_conn       zone 5;
    }

    server {
        listen           127.0.0.1:8081;
        proxy_pass       127.0.0.1:8084;
        limit_conn       zone2 1;
    }

    server {
        listen           127.0.0.1:8082;
        proxy_pass       127.0.0.1:8080;
        limit_conn       zone2 1;
    }

    server {
        listen           127.0.0.1:8083;
        proxy_pass       127.0.0.1:8080;
        limit_conn       zone 1;
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
$t->try_run('no stream limit_conn')->plan(8);

###############################################################################

like(get(), qr/200 OK/, 'passed');

# same and other zones

my $s = http(<<EOF, start => 1, sleep => 0.2);
GET / HTTP/1.0
EOF

ok($s, 'long connection');

is(get(), undef, 'rejected same zone');
like(get('127.0.0.1:8081'), qr/200 OK/, 'passed different zone');
like(get('127.0.0.1:8085'), qr/200 OK/, 'passed same zone unlimited');

ok(http(<<EOF, socket => $s), 'long connection closed');
Host: localhost

EOF

# zones proxy chain

like(get('127.0.0.1:8082'), qr/200 OK/, 'passed proxy');
is(get('127.0.0.1:8083'), undef, 'rejected proxy');

###############################################################################

sub get {
	my $peer = shift;

	my $r = http_get('/', socket => getconn($peer));
	if (!$r) {
		$r = undef;
	}

	return $r;
}

sub getconn {
	my $peer = shift;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => $peer || '127.0.0.1:8080'
	)
		or die "Can't connect to nginx: $!\n";

	return $s;
}

###############################################################################
