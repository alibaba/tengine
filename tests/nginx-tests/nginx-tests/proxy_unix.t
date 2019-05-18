#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module with unix socket.

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

eval { require IO::Socket::UNIX; };
plan(skip_all => 'IO::Socket::UNIX not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http proxy unix/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server unix:%%TESTDIR%%/unix.sock;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock;
            proxy_read_timeout 1s;
            proxy_connect_timeout 2s;
        }

        location /var {
            proxy_pass http://$arg_b;
            proxy_read_timeout 1s;
        }

        location /u {
            proxy_pass http://u;
            proxy_read_timeout 1s;
        }
    }
}

EOF

my $path = $t->testdir() . '/unix.sock';

$t->run_daemon(\&http_daemon, $path);
$t->run();

# wait for unix socket to appear

for (1 .. 50) {
	last if -S $path;
	select undef, undef, undef, 0.1;
}

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'proxy request');
like(http_get('/multi'), qr/AND-THIS/, 'proxy request with multiple packets');

unlike(http_head('/'), qr/SEE-THIS/, 'proxy head request');

like(http_get("/var?b=unix:$path:/"), qr/SEE-THIS/, 'proxy with variables');

like(http_get('/u'), qr/SEE-THIS/, 'proxy implicit upstream');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::UNIX->new(
		Proto => 'tcp',
		Local => shift,
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

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if (grep { $uri eq $_ } ('/', '/u')) {
			print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
			print $client "TEST-OK-IF-YOU-SEE-THIS"
				unless $headers =~ /^HEAD/i;

		} elsif ($uri eq '/multi') {

			print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF

			select undef, undef, undef, 0.1;
			print $client 'AND-THIS';

		} else {

			print $client <<"EOF";
HTTP/1.1 404 Not Found
Connection: close

Oops, '$uri' not found
EOF
		}

		close $client;
	}
}

###############################################################################
