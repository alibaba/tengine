#!/usr/bin/perl

# (C) Maxim Dounin

# Test for http backend returning response with Transfer-Encoding: chunked.

# Since nginx uses HTTP/1.0 in requests to backend it's backend bug, but we
# want to handle this gracefully.  And anyway chunked support will be required
# for HTTP/1.1 backend connections.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy ssi/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

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
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
        }
        location /nobuffering {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
            proxy_buffering off;
        }
        location /inmemory.html {
            ssi on;
        }
    }
}

EOF

$t->write_file('inmemory.html',
	'<!--#include virtual="/" set="one" --><!--#echo var="one" -->');

$t->run_daemon(\&http_chunked_daemon);
$t->run();

###############################################################################

{
local $TODO = 'not yet';

like(http_get('/'), qr/\x0d\x0aSEE-THIS$/s, 'chunked');
like(http_get('/nobuffering'), qr/\x0d\x0aSEE-THIS$/s, 'chunked nobuffering');
like(http_get('/inmemory.html'), qr/\x0d\x0aSEE-THIS$/s, 'chunked inmemory');
}

###############################################################################

sub http_chunked_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if (/^\x0d?\x0a?$/);
		}

		print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close
Transfer-Encoding: chunked

9
SEE-THIS

0

EOF

		close $client;
	}
}

###############################################################################
