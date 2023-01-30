#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for ignore_invalid_headers, underscores_in_headers directives.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;
use MIME::Base64 qw/ encode_base64 decode_base64 /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(12)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        ignore_invalid_headers off;

        location / {
            proxy_pass http://127.0.0.1:8085;
        }

        location /v {
            add_header X-Cookie $http_cookie;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8085;
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        underscores_in_headers on;

        location / {
            proxy_pass http://127.0.0.1:8085;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('v', '');
$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8085));

###############################################################################

my $us = 'GET / HTTP/1.0' . CRLF
	. 'x_foo: x-bar' . CRLF . CRLF;
my $us2 = 'GET / HTTP/1.0' . CRLF
	. '_foo: x-bar' . CRLF . CRLF;
my $bad = 'GET / HTTP/1.0' . CRLF
	. 'x.foo: x-bar' . CRLF . CRLF;
my $bad2 = 'GET / HTTP/1.0' . CRLF
	. '.foo: x-bar' . CRLF . CRLF;

# ignore_invalid_headers off;

like(get($us, 8080), qr/x-bar/, 'off - underscore');
like(get($us2, 8080), qr/x-bar/, 'off - underscore first');
like(get($bad, 8080), qr/x-bar/, 'off - bad');
like(get($bad2, 8080), qr/x-bar/, 'off - bad first');

# ignore_invalid_headers off; headers parsing post 8f55cb5c7e79

unlike(http('GET /v HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'coo: foo' . CRLF
	. '</kie>: x-bar' . CRLF . CRLF), qr/x-bar/, 'off - several');

# ignore_invalid_headers on;

unlike(get($us, 8081), qr/x-bar/, 'on - underscore');
unlike(get($us2, 8081), qr/x-bar/, 'on - underscore first');

# ignore_invalid_headers on; underscores_in_headers on;

like(get($us, 8082), qr/x-bar/, 'underscores_in_headers');
like(get($us2, 8082), qr/x-bar/, 'underscores_in_headers - first');

# always invalid header characters

my $bad3 = 'GET / HTTP/1.0' . CRLF
	. ':foo: x-bar' . CRLF . CRLF;
my $bad4 = 'GET / HTTP/1.0' . CRLF
	. ' foo: x-bar' . CRLF . CRLF;
my $bad5 = 'GET / HTTP/1.0' . CRLF
	. "foo\x02: x-bar" . CRLF . CRLF;

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

like(http($bad3), qr/400 Bad/, 'colon first');
like(http($bad4), qr/400 Bad/, 'space');
like(http($bad5), qr/400 Bad/, 'control');

}

###############################################################################

sub get {
	my ($msg, $port) = @_;

	my $s = IO::Socket::INET->new('127.0.0.1:' . port($port)) or die;
	my ($headers) = http($msg, socket => $s) =~ /X-Headers: (\w+)/;
	decode_base64($headers);
}

###############################################################################

sub http_daemon {
	my $once = 1;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8085),
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

		$headers = encode_base64($headers, "");

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Headers: $headers

EOF

	}
}

###############################################################################
