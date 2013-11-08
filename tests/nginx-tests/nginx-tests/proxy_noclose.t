#!/usr/bin/perl

# (C) Maxim Dounin

# Test for http backend not closing connection properly after sending full
# reply.  This is in fact backend bug, but it seems common, and anyway
# correct handling is required to support persistent connections.

# There are actually 2 nginx problems here:
#
# 1. It doesn't send reply in-time even if got Content-Length and all the data.
#
# 2. If upstream times out some data may be left in input buffer and won't be
#    sent to downstream.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(4);

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

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
        }

        location /uselen {
            proxy_pass http://127.0.0.1:8081;

            # test will wait only 2s for reply, we it will fail if
            # Content-Length not used as a hint

            proxy_read_timeout 10s;
        }
    }
}

EOF

$t->run_daemon(\&http_noclose_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'request to bad backend');
like(http_get('/multi'), qr/AND-THIS/, 'bad backend - multiple packets');
like(http_get('/uselen'), qr/SEE-THIS/, 'content-length actually used');

TODO: {
local $TODO = 'not yet';
local $SIG{__WARN__} = sub {};

like(http_get('/nolen'), qr/SEE-THIS/, 'bad backend - no content length');

}

###############################################################################

sub http_noclose_daemon {
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

		my $multi = 0;
		my $nolen = 0;

		while (<$client>) {
			$multi = 1 if /multi/;
			$nolen = 1 if /nolen/;
			last if (/^\x0d?\x0a?$/);
		}

		if ($nolen) {

			print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF
		} elsif ($multi) {

			print $client <<"EOF";
HTTP/1.1 200 OK
Content-Length: 32
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF

			select undef, undef, undef, 0.1;
			print $client 'AND-THIS';

		} else {

			print $client <<"EOF";
HTTP/1.1 200 OK
Content-Length: 24
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF
		}

		my $select = IO::Select->new($client);
		$select->can_read(10);
		close $client;
	}
}

###############################################################################
