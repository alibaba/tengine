#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module with upstream variables.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format u $uri:$upstream_response_length:$upstream_bytes_received:
                 $upstream_bytes_sent:$upstream_http_x_len;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
            access_log %%TESTDIR%%/test.log u;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->try_run('upstream_bytes_sent')->plan(4);

$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $r;

my ($l1) = ($r = http_get('/')) =~ /X-Len: (\d+)/;
like($r, qr/SEE-THIS/, 'proxy request');

my ($l2) = ($r = http_get('/multi')) =~ /X-Len: (\d+)/;
like($r, qr/AND-THIS/, 'proxy request with multiple packets');

$t->stop();

my $f = $t->read_file('test.log');
Test::Nginx::log_core('||', $f);

like($f, qr!^/:23:68:$l1:$l1!m, 'log - response length');
like($f, qr!^/multi:32:77:$l2:$l2!m, 'log - response length - multi packets');

###############################################################################

sub http_daemon {
	my ($port) = @_;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $port,
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
		my $len = length($headers);

		if ($uri eq '/') {
			print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close
X-Len: $len

EOF
			print $client "TEST-OK-IF-YOU-SEE-THIS"
				unless $headers =~ /^HEAD/i;

		} elsif ($uri eq '/multi') {

			print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close
X-Len: $len

TEST-OK-IF-YOU-SEE-THIS
EOF

			select undef, undef, undef, 0.1;
			print $client 'AND-THIS';
		}

		close $client;
	}
}

###############################################################################
