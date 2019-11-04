#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Roman Arutyunyan
# (C) Nginx, Inc.

# Test for subrequest bug with delay (see 903fb1ddc07f for details).

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

my $t = Test::Nginx->new()->has(qw/http proxy ssi/)->plan(1);

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

        location / { }
        location /delayed.html {
            ssi on;
            sendfile_max_chunk 100;
            postpone_output 0;
        }

        location /1 {
            proxy_buffers 3 256;
            proxy_buffer_size 256;
            proxy_max_temp_file_size 0;
            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF


$t->write_file('delayed.html', ('x' x 100) . '<!--#include virtual="/1"-->');

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# If a response sending is delayed by sendfile_max_chunk, and
# then we've switched to a different subrequest, which is not yet
# ready to handle corresponding write event, wev->delayed won't be
# cleared.  This results in the subrequest response not being
# sent to the client, and the whole request will hang if all proxy
# buffers will be exhausted.  Fixed in 1.11.13 (903fb1ddc07f).

like(http_get('/delayed.html'), qr/x{100}y{1024}SEE-THIS/, 'delayed');

###############################################################################

sub http_daemon {
	my ($t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	my $data = ('y' x 1024) . 'SEE-THIS';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		select undef, undef, undef, 0.5;

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

$data
EOF
	}
}

###############################################################################
