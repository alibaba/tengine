#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Test for http backend returning response with Transfer-Encoding: chunked,
# followed by some extra data.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_buffer_size 128;
        proxy_buffers 4 128;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
        }
    }
}

EOF

$t->run_daemon(\&http_chunked_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/200 OK(?!.*zzz)/s, 'chunked with extra data');

###############################################################################

sub http_chunked_daemon {
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
			last if (/^\x0d?\x0a?$/);
		}

		# return a large response start to allocate
		# multiple buffers; stop at the buffer end

		print $client ""
			. "HTTP/1.1 200 OK" . CRLF
			. "Connection: close" . CRLF
			. "Transfer-Encoding: chunked" . CRLF . CRLF
			. "80" . CRLF . ("x" x 126) . CRLF . CRLF
			. "80" . CRLF . ("x" x 126) . CRLF . CRLF
			. "80" . CRLF . ("x" x 126) . CRLF . CRLF
			. "80" . CRLF . ("x" x 126) . CRLF . CRLF
			. "20" . CRLF . ("x" x 30) . CRLF . CRLF;

		select(undef, undef, undef, 0.3);

		# fill three full buffers here, so they are
		# processed in order, regardless of the
		# p->upstream_done flag set

		print $client ""
			. "75" . CRLF . ("y" x 115) . CRLF . CRLF
			. "0" . CRLF . CRLF
			. "75" . CRLF . ("z" x 115) . CRLF . CRLF
			. "0" . CRLF . CRLF
			. "75" . CRLF . ("z" x 115) . CRLF . CRLF
			. "0" . CRLF . CRLF;

		close $client;
	}
}

###############################################################################
