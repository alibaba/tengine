#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for sub_filter buffering.

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

my $t = Test::Nginx->new()->has(qw/http sub proxy/)->plan(2)
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

        proxy_buffering off;
        proxy_http_version 1.1;

        sub_filter_types *;

        location /partial {
            proxy_pass http://127.0.0.1:8081;
            sub_filter za ZA;
        }

        location /negative {
            proxy_pass http://127.0.0.1:8081;
            sub_filter ab AB;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# partial match: the last byte matching pattern is buffered

like(http_get('/partial'), qr/xy$/, 'partial match');

# no partial match: an entire buffer is sent as is without buffering

like(http_get('/negative'), qr/xyz/, 'negative match');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if /^\x0d?\x0a?$/;
		}

		print $client
			"HTTP/1.1 200 OK" . CRLF .
			"Content-Length: 10" . CRLF . CRLF .
			"xyz";
	}
}

###############################################################################
