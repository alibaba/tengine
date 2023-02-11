#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Test for memcached backend returning extra data after trailer.

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

my $t = Test::Nginx->new()->has(qw/http rewrite memcached/)->plan(1)
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

        location / {
            set $memcached_key $uri;
            memcached_pass 127.0.0.1:8081;
        }
    }
}

EOF

$t->run_daemon(\&memcached_fake_daemon);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start fake memcached";

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'memcached data after trailer');

###############################################################################

sub memcached_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if (/\x0d\x0a$/);
		}

		print $client 'VALUE / 0 8' . CRLF;
		print $client 'SEE-THIS' . CRLF . 'END' . CRLF
			. "\0" . ("1" x 1024);

		select(undef, undef, undef, 0.2);

		print $client 'EXTRA' . CRLF;
		close $client;
	}
}

###############################################################################
