#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy_pass_request_headers, proxy_pass_request_body directives.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(3);

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

        proxy_pass_request_headers off;

        location / {
            proxy_pass http://127.0.0.1:8081;
        }

        location /body {
            proxy_pass http://127.0.0.1:8081;
            proxy_pass_request_headers on;
            proxy_pass_request_body off;
        }

        location /both {
            proxy_pass http://127.0.0.1:8081;
            proxy_pass_request_headers off;
            proxy_pass_request_body off;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(get('/', 'foo', 'bar'), qr/Header: none.*Body: bar/s, 'no headers');
like(get('/body', 'foo', 'bar'), qr/Header: foo.*Body: none/s, 'no body');
like(get('/both', 'foo', 'bar'), qr/Header: none.*Body: none/s, 'both');

###############################################################################

sub get {
	my ($uri, $header, $body) = @_;
	my $cl = length("$body\n");

	http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
X-Header: $header
Content-Length: $cl

$body
EOF
}

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

		my $r = '';

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(2);
			$client->sysread($r, 4096);
			alarm(0);
		};
		alarm(0);
		if ($@) {
			log_in("died: $@");
			next;
		}

		next if $r eq '';

		Test::Nginx::log_core('|| <<', $r);

		my $header = $r =~ /x-header: (\S+)/i && $1 || 'none';
		my $body = $r =~ /\x0d\x0a?\x0d\x0a?(.+)/ && $1 || 'none';

		print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close
X-Header: $header
X-Body: $body

EOF

		close $client;
	}
}

###############################################################################
