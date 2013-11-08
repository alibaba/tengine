#!/usr/bin/perl

# (C) Maxim Dounin

# Test for proxy cache with Transfer-Encoding: chunked.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache keys_zone=NAME:10m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_cache NAME;
            proxy_cache_valid any 1m;
            add_header X-Status $upstream_cache_status;
        }
    }
}

EOF

$t->run_daemon(\&http_chunked_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get("/"), qr/SEE-THIS/s, "chunked");
like(http_get("/"), qr/SEE-THIS.*HIT/s, "chunked cached");

###############################################################################

sub http_chunked_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
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

		print $client <<'EOF';
HTTP/1.1 200 OK
X-Test: SEE-THIS
Connection: close
Transfer-Encoding: chunked

EOF
		print $client "85" . CRLF;
		select undef, undef, undef, 0.1;
		print $client "FOO" . ("0123456789abcdef" x 8) . CRLF . CRLF;

		print $client "0" . CRLF . CRLF;
		close $client;
	}
}

###############################################################################
