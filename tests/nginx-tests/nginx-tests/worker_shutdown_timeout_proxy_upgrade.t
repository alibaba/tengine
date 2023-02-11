#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for worker_shutdown_timeout directive with http proxy upgrade stub.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_shutdown_timeout 10ms;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_set_header Upgrade foo;
            proxy_set_header Connection Upgrade;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $s = http(<<EOF, start => 1);
GET / HTTP/1.1
Host: localhost
Upgrade: foo
Connection: Upgrade

EOF

my ($sel, $buf) = IO::Select->new($s);
if ($sel->can_read(5)) {
	$s->sysread($buf, 1024);
	log_in($buf);
};

like($buf, qr!HTTP/1.1 101!, 'upgraded connection');

$t->reload();

ok($sel->can_read(3), 'upgraded connection shutdown');

undef $s;

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

	my $client;

	while ($client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		next if $headers eq '';

		print $client <<'EOF';
HTTP/1.1 101 Switching
Upgrade: foo
Connection: Upgrade

EOF

	}
}

###############################################################################
