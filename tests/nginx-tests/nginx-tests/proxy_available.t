#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module with available bytes counting.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(2);

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

        location /buffered {
            proxy_pass http://127.0.0.1:8081;
            proxy_buffer_size 512;
        }

        location /unbuffered {
            proxy_pass http://127.0.0.1:8082;
            proxy_buffer_size 512;
            proxy_buffering off;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->run_daemon(\&http_daemon, port(8082));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

# ticket #2367: socket leaks with EPOLLRDHUP
# due to missing rev->ready reset on rev->available == 0
#
# to reproduce leaks, the first part of the response should fit proxy buffer

my $s = http_get('/buffered', start => 1);
IO::Select->new($s)->can_read(3);

$t->reload();

TODO: {
local $TODO = 'not yet' if $^O eq 'linux' and !$t->has_version('1.23.1');

like(http_end($s), qr/AND-THIS/, 'zero available - buffered');

}

$s = http_get('/unbuffered', start => 1);
IO::Select->new($s)->can_read(3);

$t->stop();

like(http_end($s), qr/AND-THIS/, 'zero available - unbuffered');

$t->todo_alerts() if $^O eq 'linux' and !$t->has_version('1.23.1');

###############################################################################

sub http_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:$port",
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		next if $headers eq '';

		my $r = <<EOF;
HTTP/1.1 200 OK
Connection: close

EOF

		$r = $r . 'x' x (512 - length($r));
		print $client $r;

		select undef, undef, undef, 1.1;
		print $client 'AND-THIS';
	}
}

###############################################################################
